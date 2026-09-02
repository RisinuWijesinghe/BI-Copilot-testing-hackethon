import ballerina/file;
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

# Uploads a single local dump file to the given dated S3 path. Any failure is captured and
# returned as a result rather than being propagated, so one bad file never stops the run.
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
    s3:Error? putResult = s3Client->putObjectFromFile(bucketName, objectKey, fileMetaData.absPath);
    if putResult is s3:Error {
        log:printError("Failed to upload dump file", 'error = putResult, fileName = fileName);
        return {fileName, succeeded: false, reason: "Upload to storage failed"};
    }

    return {fileName, succeeded: true};
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
