import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerinax/aws.s3;

const string GENERIC_STORAGE_ERROR_MESSAGE = "The document storage service is currently unavailable. Please try again later.";
const string DOCUMENT_NOT_FOUND_MESSAGE = "No document found for the given reference.";
const string EXPIRATION_TOO_LONG_MESSAGE = "The requested link validity period exceeds the maximum allowed.";
const string CONTENT_TYPE_NOT_ALLOWED_MESSAGE = "Documents of this type cannot be uploaded.";
const string FOLDER_DELIMITER = "/";

# Builds the tenant-scoped S3 object key for a document reference, rejecting any reference that
# could escape the tenant's own area of the bucket (path separators, traversal segments, etc.).
#
# + tenantId - the tenant identifier
# + documentReference - the document reference supplied by the caller
# + return - the tenant-scoped object key, or `()` if the reference is not a safe, single path segment
function buildTenantObjectKey(string tenantId, string documentReference) returns string? {
    if !isSafeDocumentReference(documentReference) {
        return ();
    }
    return string `${tenantId}/${documentReference}`;
}

# Checks that a document reference is a single, safe path segment: it must not be empty, must not
# contain a path separator, and must not be a traversal segment such as `.` or `..`.
#
# + documentReference - the document reference supplied by the caller
# + return - true if the reference is safe to use as a single path segment
function isSafeDocumentReference(string documentReference) returns boolean {
    if documentReference.trim().length() == 0 {
        return false;
    }
    if documentReference.includes("/") || documentReference.includes("\\") {
        return false;
    }
    if documentReference == "." || documentReference == ".." {
        return false;
    }
    return true;
}

# Builds the tenant-scoped S3 prefix for a folder path, rejecting any path that could escape the
# tenant's own area of the bucket (traversal segments, backslashes, leading slashes, etc.).
# An empty folder path refers to the root of the tenant's area.
#
# + tenantId - the tenant identifier
# + folderPath - the folder path supplied by the caller, empty for the tenant's root
# + return - the tenant-scoped S3 prefix (always ending in `/`), or `()` if the path is unsafe
function buildTenantFolderPrefix(string tenantId, string folderPath) returns string? {
    if !isSafeFolderPath(folderPath) {
        return ();
    }
    if folderPath.length() == 0 {
        return string `${tenantId}/`;
    }
    return string `${tenantId}/${folderPath}/`;
}

# Checks that a folder path is safe: it must not contain a traversal segment (`.` or `..`), must
# not contain a backslash, and must not start or end with a slash. An empty path (the tenant's
# root) is safe.
#
# + folderPath - the folder path supplied by the caller
# + return - true if the path is safe to use as a tenant-scoped S3 prefix
function isSafeFolderPath(string folderPath) returns boolean {
    if folderPath.length() == 0 {
        return true;
    }
    if folderPath.includes("\\") || folderPath.startsWith("/") || folderPath.endsWith("/") {
        return false;
    }
    string:RegExp separator = re `/`;
    string[] segments = separator.split(folderPath);
    foreach string segment in segments {
        if segment.trim().length() == 0 || segment == "." || segment == ".." {
            return false;
        }
    }
    return true;
}

# Resolves the expiration period to apply for a link, rejecting outright any request for a period
# longer than the configured maximum rather than silently clamping it.
#
# + requestedExpirationMinutes - the caller-requested expiration period, or `()` to use the default
# + return - the resolved expiration period in minutes, or `()` if the requested period exceeds the maximum
function resolveLinkExpirationMinutes(int? requestedExpirationMinutes) returns int? {
    if requestedExpirationMinutes is () {
        return defaultLinkExpirationMinutes;
    }
    if requestedExpirationMinutes <= 0 || requestedExpirationMinutes > maxLinkExpirationMinutes {
        return ();
    }
    return requestedExpirationMinutes;
}

# Computes the ISO-8601 expiry timestamp for a link that is valid starting now for the given period.
#
# + expirationMinutes - the link validity period in minutes
# + return - the ISO-8601 timestamp at which the link expires
function computeExpiresAt(int expirationMinutes) returns string {
    time:Utc expiresAtUtc = time:utcAddSeconds(time:utcNow(), <decimal>expirationMinutes * 60);
    return time:utcToString(expiresAtUtc);
}

# Handles creating a short-lived download link for a document.
# A link is only ever issued for a document that is confirmed to exist; otherwise a plain not
# found is returned so the caller never receives a link that could 404 later. A document reference
# that attempts to escape the tenant's own area of the bucket is rejected identically to a document
# that does not exist.
#
# + tenantId - the tenant identifier
# + documentReference - the document reference
# + requestedExpirationMinutes - the caller-requested link validity period, or `()` to use the default
# + return - the short-lived download link, a not found, a bad request if the requested validity period
# is too long, or a generic server error
function handleGetDownloadLink(string tenantId, string documentReference, int? requestedExpirationMinutes)
        returns DownloadLink|http:NotFound|http:BadRequest|http:InternalServerError {
    string? objectKey = buildTenantObjectKey(tenantId, documentReference);
    if objectKey is () {
        return <http:NotFound>{body: {message: DOCUMENT_NOT_FOUND_MESSAGE}};
    }

    int? expirationMinutes = resolveLinkExpirationMinutes(requestedExpirationMinutes);
    if expirationMinutes is () {
        return <http:BadRequest>{body: {message: EXPIRATION_TOO_LONG_MESSAGE}};
    }

    boolean|s3:Error existsResult = s3Client->doesObjectExist(bucketName, objectKey);
    if existsResult is s3:Error {
        log:printError("Failed to check document existence in storage", 'error = existsResult);
        return <http:InternalServerError>{body: {message: GENERIC_STORAGE_ERROR_MESSAGE}};
    }
    if !existsResult {
        return <http:NotFound>{body: {message: DOCUMENT_NOT_FOUND_MESSAGE}};
    }

    string|s3:Error presignedUrl = s3Client->createPresignedUrl(bucketName, objectKey,
            expirationMinutes = expirationMinutes, httpMethod = s3:GET);
    if presignedUrl is s3:Error {
        log:printError("Failed to create presigned download link", 'error = presignedUrl);
        return <http:InternalServerError>{body: {message: GENERIC_STORAGE_ERROR_MESSAGE}};
    }

    return {
        url: presignedUrl,
        expiresAt: computeExpiresAt(expirationMinutes)
    };
}

# Handles creating a short-lived upload link for a named document. Only documents whose content
# type is on the configured allow-list may be uploaded; anything else is refused before a link is
# ever issued. A document reference that attempts to escape the tenant's own area of the bucket is
# rejected identically to a document that does not exist.
#
# + tenantId - the tenant identifier
# + documentReference - the document reference
# + uploadLinkRequest - the requested content type and, optionally, the link validity period
# + return - the short-lived upload link, a not found if the reference is unsafe, a bad request if
# the content type is not allowed or the requested validity period is too long, or a generic server error
function handleGetUploadLink(string tenantId, string documentReference, UploadLinkRequest uploadLinkRequest)
        returns UploadLink|http:NotFound|http:BadRequest|http:InternalServerError {
    string? objectKey = buildTenantObjectKey(tenantId, documentReference);
    if objectKey is () {
        return <http:NotFound>{body: {message: DOCUMENT_NOT_FOUND_MESSAGE}};
    }

    if !allowedUploadContentTypes.some(allowedContentType => allowedContentType == uploadLinkRequest.contentType) {
        return <http:BadRequest>{body: {message: CONTENT_TYPE_NOT_ALLOWED_MESSAGE}};
    }

    int? expirationMinutes = resolveLinkExpirationMinutes(uploadLinkRequest?.expirationMinutes);
    if expirationMinutes is () {
        return <http:BadRequest>{body: {message: EXPIRATION_TOO_LONG_MESSAGE}};
    }

    string|s3:Error presignedUrl = s3Client->createPresignedUrl(bucketName, objectKey,
            expirationMinutes = expirationMinutes, httpMethod = s3:PUT, contentType = uploadLinkRequest.contentType);
    if presignedUrl is s3:Error {
        log:printError("Failed to create presigned upload link", 'error = presignedUrl);
        return <http:InternalServerError>{body: {message: GENERIC_STORAGE_ERROR_MESSAGE}};
    }

    return {
        url: presignedUrl,
        expiresAt: computeExpiresAt(expirationMinutes)
    };
}

# Handles reporting whether a document exists along with its size, type and last modified time.
# A document reference that attempts to escape the tenant's own area of the bucket is rejected
# identically to a document that does not exist.
#
# + tenantId - the tenant identifier
# + documentReference - the document reference
# + return - the document status, a not found, or a generic server error
function handleGetDocumentStatus(string tenantId, string documentReference) returns DocumentStatus|http:NotFound|http:InternalServerError {
    string? objectKey = buildTenantObjectKey(tenantId, documentReference);
    if objectKey is () {
        return <http:NotFound>{body: {message: DOCUMENT_NOT_FOUND_MESSAGE}};
    }

    boolean|s3:Error existsResult = s3Client->doesObjectExist(bucketName, objectKey);
    if existsResult is s3:Error {
        log:printError("Failed to check document existence in storage", 'error = existsResult);
        return <http:InternalServerError>{body: {message: GENERIC_STORAGE_ERROR_MESSAGE}};
    }
    if !existsResult {
        return <http:NotFound>{body: {message: DOCUMENT_NOT_FOUND_MESSAGE}};
    }

    s3:ObjectMetadata|s3:Error metadataResult = s3Client->getObjectMetadata(bucketName, objectKey);
    if metadataResult is s3:Error {
        log:printError("Failed to fetch document metadata from storage", 'error = metadataResult);
        return <http:InternalServerError>{body: {message: GENERIC_STORAGE_ERROR_MESSAGE}};
    }

    return {
        exists: true,
        sizeInBytes: metadataResult.contentLength,
        contentType: metadataResult.contentType ?: "application/octet-stream",
        lastModified: metadataResult.lastModified
    };
}

# Handles listing the documents directly inside a tenant's folder - not documents nested in
# subfolders - each with a ready-to-use download link. An empty folder yields an empty page rather
# than an error. A folder path that attempts to escape the tenant's own area of the bucket is
# rejected identically to a folder that does not exist (an empty listing).
#
# + tenantId - the tenant identifier
# + folderPath - the folder path to list, empty for the tenant's root
# + pageSize - the maximum number of documents to return in this page
# + pageToken - the continuation token returned by a previous call, or `()` to fetch the first page
# + return - the page of documents with their download links, a bad request if the requested link
# validity period is too long, or a generic server error
function handleListFolder(string tenantId, string folderPath, int pageSize, string? pageToken)
        returns FolderListing|http:BadRequest|http:InternalServerError {
    string? folderPrefix = buildTenantFolderPrefix(tenantId, folderPath);
    if folderPrefix is () {
        return {documents: []};
    }

    int? expirationMinutes = resolveLinkExpirationMinutes(());
    if expirationMinutes is () {
        return <http:BadRequest>{body: {message: EXPIRATION_TOO_LONG_MESSAGE}};
    }

    s3:ListObjectsResponse|s3:Error listResult = s3Client->listObjects(bucketName, prefix = folderPrefix,
            delimiter = FOLDER_DELIMITER, maxKeys = pageSize, continuationToken = pageToken ?: "");
    if listResult is s3:Error {
        log:printError("Failed to list folder contents in storage", 'error = listResult);
        return <http:InternalServerError>{body: {message: GENERIC_STORAGE_ERROR_MESSAGE}};
    }

    FolderEntry[] documents = [];
    foreach s3:S3Object s3Object in listResult.objects {
        string documentName = s3Object.key.substring(folderPrefix.length());
        if documentName.length() == 0 {
            // The folder placeholder object itself, not an actual document.
            continue;
        }

        string|s3:Error presignedUrl = s3Client->createPresignedUrl(bucketName, s3Object.key,
                expirationMinutes = expirationMinutes, httpMethod = s3:GET);
        if presignedUrl is s3:Error {
            log:printError("Failed to create presigned download link for a folder entry", 'error = presignedUrl);
            return <http:InternalServerError>{body: {message: GENERIC_STORAGE_ERROR_MESSAGE}};
        }

        documents.push({
            name: documentName,
            sizeInBytes: s3Object.size,
            lastModified: s3Object.lastModified,
            downloadLink: {url: presignedUrl, expiresAt: computeExpiresAt(expirationMinutes)}
        });
    }

    if listResult.isTruncated {
        string? nextContinuationToken = listResult.nextContinuationToken;
        if nextContinuationToken is string {
            return {documents, nextPageToken: nextContinuationToken};
        }
    }
    return {documents};
}
