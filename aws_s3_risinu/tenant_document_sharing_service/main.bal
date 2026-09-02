import ballerina/http;

service /documents on new http:Listener(servicePort) {

    # Issues a short-lived link the browser can use to download a document directly from storage.
    # A link is only ever issued for a document that is confirmed to exist. A document reference
    # that attempts to escape the tenant's own area of the bucket is rejected exactly like a
    # document that does not exist.
    #
    # + tenantId - the identifier of the tenant that owns the document
    # + documentReference - the reference identifying the document
    # + expirationMinutes - the requested link validity period in minutes; defaults to the service default
    # if omitted, and is rejected outright if it exceeds the configured maximum
    # + return - the short-lived download link, a not found if the document does not exist, a bad request
    # if the requested validity period is too long, or a generic server error if the storage layer fails
    resource function get [string tenantId]/[string documentReference]/download\-link(int? expirationMinutes = ())
            returns DownloadLink|http:NotFound|http:BadRequest|http:InternalServerError {
        return handleGetDownloadLink(tenantId, documentReference, expirationMinutes);
    }

    # Issues a short-lived link the browser can use to upload a named document's bytes directly to
    # storage. Only content types on the configured allow-list may be uploaded. A document reference
    # that attempts to escape the tenant's own area of the bucket is rejected exactly like a document
    # that does not exist.
    #
    # + tenantId - the identifier of the tenant that will own the document
    # + documentReference - the reference identifying the document
    # + uploadLinkRequest - the requested content type and, optionally, the link validity period
    # + return - the short-lived upload link, a not found if the reference is unsafe, a bad request if the
    # content type is not allowed or the requested validity period is too long, or a generic server error
    resource function post [string tenantId]/[string documentReference]/upload\-link(@http:Payload UploadLinkRequest uploadLinkRequest)
            returns UploadLink|http:NotFound|http:BadRequest|http:InternalServerError {
        return handleGetUploadLink(tenantId, documentReference, uploadLinkRequest);
    }

    # Reports whether a document exists along with its size, type and when it was last changed. A
    # document reference that attempts to escape the tenant's own area of the bucket is rejected
    # exactly like a document that does not exist.
    #
    # + tenantId - the identifier of the tenant that owns the document
    # + documentReference - the reference identifying the document
    # + return - the document status, a not found if the document does not exist,
    # or a generic server error if the storage layer fails
    resource function get [string tenantId]/[string documentReference]() returns DocumentStatus|http:NotFound|http:InternalServerError {
        return handleGetDocumentStatus(tenantId, documentReference);
    }
}
