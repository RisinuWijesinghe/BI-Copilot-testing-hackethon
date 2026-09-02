import ballerina/file;
import ballerina/io;
import ballerina/log;
import ballerina/time;
import ballerinax/aws.s3;

const string BUCKET_ALREADY_OWNED_MARKER = "BucketAlreadyOwnedByYou";
const string BUCKET_ALREADY_EXISTS_MARKER = "BucketAlreadyExists";

# Ensures the destination bucket exists in the configured region, creating it if it is not there.
# A bucket that already exists and is owned by us is a normal startup outcome. A bucket name that
# is already taken by another AWS account is a fatal condition: the program must stop immediately
# rather than retrying or continuing with a bucket it does not control.
#
# + return - `()` once the bucket is confirmed to exist and be ours, or an `error` describing why
# the program cannot proceed
function ensureDestinationBucketExists() returns error? {
    s3:Error? createResult = s3Client->createBucket(bucketName);
    if createResult is () {
        log:printInfo("Destination bucket created", bucketName = bucketName);
        return;
    }

    string errorMessage = createResult.message();
    if errorMessage.includes(BUCKET_ALREADY_OWNED_MARKER) {
        log:printInfo("Destination bucket already exists and is ours, continuing", bucketName = bucketName);
        return;
    }
    if errorMessage.includes(BUCKET_ALREADY_EXISTS_MARKER) {
        return error(string `The bucket name "${bucketName}" is already taken by another AWS account. ` +
                "Choose a different bucket name or use a bucket you own.");
    }

    return error(string `Failed to ensure the destination bucket exists: ${errorMessage}`);
}

# Builds the dated S3 path prefix under which tonight's dumps are uploaded.
#
# + return - the dated path prefix, e.g. `2026-09-02`
function buildDatedPath() returns string {
    time:Utc now = time:utcNow();
    time:Civil civil = time:utcToCivil(now);
    string year = civil.year.toString();
    string month = padTwoDigits(civil.month);
    string day = padTwoDigits(civil.day);
    return string `${year}-${month}-${day}`;
}

# Pads a one- or two-digit number with a leading zero so it is always two digits wide.
#
# + value - the number to pad
# + return - the two-digit, zero-padded representation
function padTwoDigits(int value) returns string {
    if value < 10 {
        return string `0${value}`;
    }
    return value.toString();
}

# Lists the regular files directly inside the local dump directory. Subdirectories are skipped;
# only their names are logged so the operator is aware they were not walked.
#
# + return - the metadata of the regular files found, or an `error` if the directory cannot be read
function listDumpFiles() returns file:MetaData[]|error {
    file:MetaData[] entries = check file:readDir(dumpDirectoryPath);
    file:MetaData[] regularFiles = [];
    foreach file:MetaData entry in entries {
        if entry.dir {
            string subdirectoryName = check file:basename(entry.absPath);
            log:printWarn("Skipping subdirectory in dump directory", subdirectoryName = subdirectoryName);
            continue;
        }
        regularFiles.push(entry);
    }
    return regularFiles;
}

# Uploads a single local dump file to the given dated S3 path. Files at or above the configured
# multipart threshold are uploaded in parts so the whole file is never read into memory at once;
# smaller files take the simple, single-request path. Any failure is captured and returned as a
# result rather than being propagated, so one bad file never stops the run.
#
# + fileMetaData - the metadata of the local file to upload
# + datedPath - the dated S3 path prefix to upload under
# + return - the outcome of the upload for this file
function uploadDumpFile(file:MetaData fileMetaData, string datedPath) returns FileUploadResult {
    string|file:Error fileName = file:basename(fileMetaData.absPath);
    if fileName is file:Error {
        return {fileName: fileMetaData.absPath, succeeded: false, reason: "Could not determine the file name"};
    }

    string objectKey = string `${datedPath}/${fileName}`;
    if fileMetaData.size >= multipartThresholdInBytes {
        error? multipartResult = uploadFileAsMultipart(objectKey, fileMetaData.absPath, fileName);
        if multipartResult is error {
            return {fileName, succeeded: false, reason: "Upload to storage failed"};
        }
        return {fileName, succeeded: true};
    }

    s3:Error? putResult = s3Client->putObjectFromFile(bucketName, objectKey, fileMetaData.absPath);
    if putResult is s3:Error {
        log:printError("Failed to upload dump file", 'error = putResult, fileName = fileName);
        return {fileName, succeeded: false, reason: "Upload to storage failed"};
    }

    return {fileName, succeeded: true};
}

# Uploads a large local dump file to S3 as a multipart upload, streaming it in fixed-size chunks
# so the whole file is never held in memory at once.
#
# If any part fails to upload, or the upload cannot be finalized, the in-progress multipart
# upload is aborted so no orphaned parts are left behind - a failed transfer must never leave a
# partial object, or partial parts that AWS would otherwise keep billing for, in the bucket. Only
# once every part has succeeded and the upload has been completed does the object become visible
# in the bucket, so a failure partway through can never appear as a complete object.
#
# + objectKey - the destination S3 object key
# + filePath - the absolute local path of the file to upload
# + fileName - the file name, used only for logging
# + return - `()` on success, or an `error` if the upload failed and was aborted
function uploadFileAsMultipart(string objectKey, string filePath, string fileName) returns error? {
    string|s3:Error uploadId = s3Client->createMultipartUpload(bucketName, objectKey);
    if uploadId is s3:Error {
        log:printError("Failed to start multipart upload for dump file", 'error = uploadId, fileName = fileName);
        return error("Failed to start multipart upload");
    }

    int[]|error uploadOutcome = uploadAllPartsAndComplete(objectKey, filePath, fileName, uploadId);
    if uploadOutcome is error {
        abortMultipartUpload(objectKey, uploadId, fileName);
        return uploadOutcome;
    }
}

# Streams a local file in fixed-size chunks, uploading each chunk as a part of the given
# multipart upload, and completes the upload once every part has succeeded.
#
# + objectKey - the destination S3 object key
# + filePath - the absolute local path of the file to upload
# + fileName - the file name, used only for logging
# + uploadId - the identifier of the in-progress multipart upload
# + return - the part numbers uploaded on success, or an `error` if any part or the completion failed
function uploadAllPartsAndComplete(string objectKey, string filePath, string fileName, string uploadId) returns int[]|error {
    stream<io:Block, io:Error?>|io:Error blockStream = io:fileReadBlocksAsStream(filePath, multipartChunkSizeInBytes);
    if blockStream is io:Error {
        log:printError("Failed to open dump file for multipart upload", 'error = blockStream, fileName = fileName);
        return error("Failed to read the file for multipart upload");
    }

    int[] partNumbers = [];
    string[] etags = [];
    int partNumber = 1;
    error? iterationError = from io:Block block in blockStream
        do {
            stream<byte[], error?> partStream = [block].toStream();
            string|s3:Error etag = s3Client->uploadPartAsStream(bucketName, objectKey, uploadId, partNumber, partStream,
                    contentLength = block.length());
            if etag is s3:Error {
                log:printError("Failed to upload a part of a dump file", 'error = etag, fileName = fileName,
                        partNumber = partNumber);
                fail error(string `Failed to upload part ${partNumber}`);
            }
            partNumbers.push(partNumber);
            etags.push(etag);
            partNumber += 1;
        };
    check closeBlockStream(blockStream, fileName);
    if iterationError is error {
        return iterationError;
    }

    if partNumbers.length() == 0 {
        log:printError("Dump file produced no parts to upload", fileName = fileName);
        return error("File produced no data to upload");
    }

    s3:Error? completeResult = s3Client->completeMultipartUpload(bucketName, objectKey, uploadId, partNumbers, etags);
    if completeResult is s3:Error {
        log:printError("Failed to complete multipart upload for dump file", 'error = completeResult, fileName = fileName);
        return error("Failed to complete multipart upload");
    }

    return partNumbers;
}

# Closes a file block stream, logging - but not failing the run over - any error encountered
# while closing it.
#
# + blockStream - the block stream to close
# + fileName - the file name, used only for logging
# + return - always `()`
function closeBlockStream(stream<io:Block, io:Error?> blockStream, string fileName) returns error? {
    io:Error? closeResult = blockStream.close();
    if closeResult is io:Error {
        log:printWarn("Failed to close dump file after multipart upload", 'error = closeResult, fileName = fileName);
    }
}

# Aborts an in-progress multipart upload so no orphaned parts are left behind and billed for.
# Logs a warning, rather than failing the run, if the abort itself fails - the caller has already
# recorded the file as failed regardless.
#
# + objectKey - the destination S3 object key
# + uploadId - the identifier of the in-progress multipart upload to abort
# + fileName - the file name, used only for logging
function abortMultipartUpload(string objectKey, string uploadId, string fileName) {
    s3:Error? abortResult = s3Client->abortMultipartUpload(bucketName, objectKey, uploadId);
    if abortResult is s3:Error {
        log:printWarn("Failed to abort an incomplete multipart upload; orphaned parts may remain in storage",
                'error = abortResult, fileName = fileName);
    }
}

# Runs the nightly ingest: walks the local dump directory and uploads each file found under the
# given dated path, recording the outcome of every file so the run continues even when individual
# files fail.
#
# + datedPath - the dated S3 path prefix to upload under
# + return - the overall ingest summary, or an `error` if the local dump directory cannot be read
function ingestDumpFiles(string datedPath) returns IngestSummary|error {
    file:MetaData[] dumpFiles = check listDumpFiles();

    FileUploadResult[] results = [];
    int succeededCount = 0;
    int failedCount = 0;
    foreach file:MetaData fileMetaData in dumpFiles {
        FileUploadResult result = uploadDumpFile(fileMetaData, datedPath);
        results.push(result);
        if result.succeeded {
            succeededCount += 1;
        } else {
            failedCount += 1;
        }
    }

    return {
        bucketName,
        datedPath,
        totalFileCount: dumpFiles.length(),
        succeededCount,
        failedCount,
        results
    };
}

# Prints a customer-safe summary of the ingest run to the console. Only file names, counts, and
# generic reasons are printed - never credentials, AWS error codes, or other internal details.
#
# + summary - the ingest summary to print
function printIngestSummary(IngestSummary summary) {
    log:printInfo("Nightly dump ingest summary", bucketName = summary.bucketName, datedPath = summary.datedPath,
            totalFileCount = summary.totalFileCount, succeededCount = summary.succeededCount,
            failedCount = summary.failedCount);

    foreach FileUploadResult result in summary.results {
        if result.succeeded {
            log:printInfo(string `  [OK]   ${result.fileName}`);
        } else {
            log:printInfo(string `  [FAIL] ${result.fileName} - ${result.reason ?: "unknown reason"}`);
        }
    }
}

# Determines whether an S3 object's age exceeds the configured retention period.
#
# + lastModified - the object's last modified timestamp, as an RFC 3339 string
# + return - true if the object is older than the configured retention period, or an `error` if the
# timestamp cannot be parsed
function isPastRetention(string lastModified) returns boolean|error {
    time:Utc lastModifiedUtc = check time:utcFromString(lastModified);
    time:Seconds ageInSeconds = time:utcDiffSeconds(time:utcNow(), lastModifiedUtc);
    decimal ageInDays = ageInSeconds / (24 * 60 * 60);
    return ageInDays >= <decimal>retentionDays;
}

# Builds the archive-area object key for a given backup object key.
#
# + objectKey - the backup object's key in the incoming area
# + return - the corresponding key under the long-term archive area
function buildArchiveObjectKey(string objectKey) returns string => archiveKeyPrefix + objectKey;

# Moves a single aged backup object into the long-term archive area: the object is copied to the
# archive area in the cheaper storage class, the copy is confirmed to exist, and only then is the
# original removed. Nothing is ever deleted unless its archived copy is confirmed to exist first.
#
# + objectKey - the backup object's key in the incoming area
# + return - `()` once the object has been safely archived, or an `error` describing what went wrong
function archiveAgedObject(string objectKey) returns error? {
    string archiveObjectKey = buildArchiveObjectKey(objectKey);

    s3:Error? copyResult = s3Client->copyObject(bucketName, objectKey, bucketName, archiveObjectKey,
            storageClass = archiveStorageClass);
    if copyResult is s3:Error {
        log:printError("Failed to copy aged backup to the archive area", 'error = copyResult, objectKey = objectKey);
        return error("Failed to copy the backup to the archive area");
    }

    boolean|s3:Error archiveExistsResult = s3Client->doesObjectExist(bucketName, archiveObjectKey);
    if archiveExistsResult is s3:Error {
        log:printError("Failed to confirm the archived copy exists", 'error = archiveExistsResult, objectKey = objectKey);
        return error("Failed to confirm the archived copy exists");
    }
    if !archiveExistsResult {
        log:printError("Archived copy could not be confirmed after copy; leaving the original in place",
                objectKey = objectKey);
        return error("Archived copy could not be confirmed");
    }

    s3:Error? deleteResult = s3Client->deleteObject(bucketName, objectKey);
    if deleteResult is s3:Error {
        log:printError("Backup was archived but removing the original failed; a copy still exists in the " +
                "archive area and the original remains in place", 'error = deleteResult, objectKey = objectKey);
        return error("Failed to remove the original after archiving");
    }
}

# Sweeps the backup area for objects older than the configured retention period and moves each one
# into the long-term archive area. A sweep that finds nothing to do is a normal, quiet outcome, not
# a failure. Objects already under the archive prefix are never reconsidered.
#
# + return - the sweep summary, or an `error` if the backup area could not be listed
function sweepRetention() returns RetentionSweepSummary|error {
    s3:S3Object[] agedObjects = check listAgedBackupObjects();

    ArchiveMoveResult[] results = [];
    int movedCount = 0;
    int failedCount = 0;
    foreach s3:S3Object s3Object in agedObjects {
        error? archiveResult = archiveAgedObject(s3Object.key);
        if archiveResult is error {
            results.push({objectKey: s3Object.key, succeeded: false, reason: "Archiving failed"});
            failedCount += 1;
        } else {
            results.push({objectKey: s3Object.key, succeeded: true});
            movedCount += 1;
        }
    }

    return {
        consideredCount: agedObjects.length(),
        movedCount,
        failedCount,
        results
    };
}

# Lists the backup objects in the bucket that are older than the configured retention period,
# excluding anything already under the archive prefix.
#
# + return - the aged backup objects found, or an `error` if the bucket could not be listed
function listAgedBackupObjects() returns s3:S3Object[]|error {
    s3:ListObjectsResponse|s3:Error listResult = s3Client->listObjects(bucketName);
    if listResult is s3:Error {
        log:printError("Failed to list backup objects for the retention sweep", 'error = listResult);
        return error("Failed to list backup objects for the retention sweep");
    }

    s3:S3Object[] agedObjects = [];
    foreach s3:S3Object s3Object in listResult.objects {
        if s3Object.key.startsWith(archiveKeyPrefix) {
            continue;
        }
        boolean|error pastRetention = isPastRetention(s3Object.lastModified);
        if pastRetention is error {
            log:printWarn("Could not determine the age of a backup object; skipping it for this sweep",
                    'error = pastRetention, objectKey = s3Object.key);
            continue;
        }
        if pastRetention {
            agedObjects.push(s3Object);
        }
    }
    return agedObjects;
}

# Prints a customer-safe summary of the retention sweep to the console. A sweep that finds nothing
# to archive is reported plainly as a normal outcome, not as a failure. Only object keys, counts,
# and generic reasons are printed - never credentials, AWS error codes, or other internal details.
#
# + summary - the retention sweep summary to print
function printRetentionSweepSummary(RetentionSweepSummary summary) {
    if summary.consideredCount == 0 {
        log:printInfo("Retention sweep summary: no backups older than the retention period were found");
        return;
    }

    log:printInfo("Retention sweep summary", consideredCount = summary.consideredCount,
            movedCount = summary.movedCount, failedCount = summary.failedCount);

    foreach ArchiveMoveResult result in summary.results {
        if result.succeeded {
            log:printInfo(string `  [ARCHIVED] ${result.objectKey}`);
        } else {
            log:printInfo(string `  [FAIL]     ${result.objectKey} - ${result.reason ?: "unknown reason"}`);
        }
    }
}
