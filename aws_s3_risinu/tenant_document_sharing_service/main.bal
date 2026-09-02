import ballerina/http;

service /documents on new http:Listener(servicePort) {

    # Issues a short-lived link the browser can use to download a document directly from storage.
    # A link is only ever issued for a document that is confirmed to exist.
    #
    # + documentReference - the reference identifying the document
    # + return - the short-lived download link, a not found if the document does not exist,
    # or a generic server error if the storage layer fails
    resource function get [string documentReference]/download\-link() returns DownloadLink|http:NotFound|http:InternalServerError {
        return handleGetDownloadLink(documentReference);
    }

    # Reports whether a document exists along with its size, type and when it was last changed.
    #
    # + documentReference - the reference identifying the document
    # + return - the document status, a not found if the document does not exist,
    # or a generic server error if the storage layer fails
    resource function get [string documentReference]() returns DocumentStatus|http:NotFound|http:InternalServerError {
        return handleGetDocumentStatus(documentReference);
    }
}
