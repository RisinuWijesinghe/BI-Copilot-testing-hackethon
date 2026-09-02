import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerinax/aws.s3;

const string GENERIC_STORAGE_ERROR_MESSAGE = "The document storage service is currently unavailable. Please try again later.";
const string DOCUMENT_NOT_FOUND_MESSAGE = "No document found for the given reference.";
const string EXPIRATION_TOO_LONG_MESSAGE = "The requested link validity period exceeds the maximum allowed.";
const string CONTENT_TYPE_NOT_ALLOWED_MESSAGE = "Documents of this type cannot be uploaded.";

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
