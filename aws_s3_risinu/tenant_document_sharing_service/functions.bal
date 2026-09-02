import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerinax/aws.s3;

const string GENERIC_STORAGE_ERROR_MESSAGE = "The document storage service is currently unavailable. Please try again later.";
const string DOCUMENT_NOT_FOUND_MESSAGE = "No document found for the given reference.";

# Handles creating a short-lived download link for a document.
# A link is only ever issued for a document that is confirmed to exist; otherwise a plain not
# found is returned so the caller never receives a link that could 404 later.
#
# + documentReference - the document reference
# + return - the short-lived download link, a not found, or a generic server error
function handleGetDownloadLink(string documentReference) returns DownloadLink|http:NotFound|http:InternalServerError {
    boolean|s3:Error existsResult = s3Client->doesObjectExist(bucketName, documentReference);
    if existsResult is s3:Error {
        log:printError("Failed to check document existence in storage", 'error = existsResult);
        return <http:InternalServerError>{body: {message: GENERIC_STORAGE_ERROR_MESSAGE}};
    }
    if !existsResult {
        return <http:NotFound>{body: {message: DOCUMENT_NOT_FOUND_MESSAGE}};
    }

    string|s3:Error presignedUrl = s3Client->createPresignedUrl(bucketName, documentReference,
            expirationMinutes = downloadLinkExpirationMinutes, httpMethod = s3:GET);
    if presignedUrl is s3:Error {
        log:printError("Failed to create presigned download link", 'error = presignedUrl);
        return <http:InternalServerError>{body: {message: GENERIC_STORAGE_ERROR_MESSAGE}};
    }

    time:Utc expiresAtUtc = time:utcAddSeconds(time:utcNow(), <decimal>downloadLinkExpirationMinutes * 60);
    return {
        url: presignedUrl,
        expiresAt: time:utcToString(expiresAtUtc)
    };
}

# Handles reporting whether a document exists along with its size, type and last modified time.
#
# + documentReference - the document reference
# + return - the document status, a not found, or a generic server error
function handleGetDocumentStatus(string documentReference) returns DocumentStatus|http:NotFound|http:InternalServerError {
    boolean|s3:Error existsResult = s3Client->doesObjectExist(bucketName, documentReference);
    if existsResult is s3:Error {
        log:printError("Failed to check document existence in storage", 'error = existsResult);
        return <http:InternalServerError>{body: {message: GENERIC_STORAGE_ERROR_MESSAGE}};
    }
    if !existsResult {
        return <http:NotFound>{body: {message: DOCUMENT_NOT_FOUND_MESSAGE}};
    }

    s3:ObjectMetadata|s3:Error metadataResult = s3Client->getObjectMetadata(bucketName, documentReference);
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
