import ballerina/http;
import ballerina/test;
import ballerinax/aws.s3;

const string TEST_TENANT_ID = "tenant-a";
const string TEST_DOCUMENT_REFERENCE = "invoice.pdf";

# A download link must never be issued for a document that is not actually there - the caller
# must get a plain not found instead.
@test:Config {}
function testGetDownloadLinkForMissingDocument() returns error? {
    test:prepare(s3Client).when("doesObjectExist").thenReturn(false);

    DownloadLink|http:NotFound|http:BadRequest|http:InternalServerError result =
        handleGetDownloadLink(TEST_TENANT_ID, TEST_DOCUMENT_REFERENCE, ());

    test:assertTrue(result is http:NotFound, msg = "Expected a not found response for a document that does not exist");
}

# A request for a validity period longer than the configured maximum must be rejected outright,
# never silently clamped.
@test:Config {}
function testGetDownloadLinkWithExpiryLongerThanCap() returns error? {
    DownloadLink|http:NotFound|http:BadRequest|http:InternalServerError result =
        handleGetDownloadLink(TEST_TENANT_ID, TEST_DOCUMENT_REFERENCE, maxLinkExpirationMinutes + 1);

    test:assertTrue(result is http:BadRequest,
            msg = "Expected a bad request response when the requested validity period exceeds the maximum");
}

# Only a small allow-list of document types may be uploaded; anything else must be refused
# before a link is ever issued.
@test:Config {}
function testGetUploadLinkForDisallowedContentType() returns error? {
    UploadLinkRequest uploadLinkRequest = {contentType: "application/x-msdownload"};

    UploadLink|http:NotFound|http:BadRequest|http:InternalServerError result =
        handleGetUploadLink(TEST_TENANT_ID, TEST_DOCUMENT_REFERENCE, uploadLinkRequest);

    test:assertTrue(result is http:BadRequest, msg = "Expected a bad request response for a disallowed content type");
}

# A tenant must never be able to obtain a link to another tenant's document, including by putting
# slashes or path tricks in the document name - and this must look identical to asking for a
# document that does not exist.
@test:Config {}
function testGetDownloadLinkRejectsCrossTenantPathTraversal() returns error? {
    string maliciousDocumentReference = "../tenant-b/secret.pdf";

    DownloadLink|http:NotFound|http:BadRequest|http:InternalServerError result =
        handleGetDownloadLink(TEST_TENANT_ID, maliciousDocumentReference, ());

    test:assertTrue(result is http:NotFound,
            msg = "Expected a not found response, indistinguishable from a missing document, for a path traversal attempt");
}

# A folder with nothing in it must yield an empty result, not an error.
@test:Config {}
function testListFolderReturnsEmptyResultForEmptyFolder() returns error? {
    s3:ListObjectsResponse emptyListing = {objects: [], count: 0, isTruncated: false};
    test:prepare(s3Client).when("listObjects").thenReturn(emptyListing);

    FolderListing|http:BadRequest|http:InternalServerError result = handleListFolder(TEST_TENANT_ID, "", 100, ());

    if result !is FolderListing {
        test:assertFail(msg = "Expected a folder listing response for an empty folder");
    }

    FolderListing folderListing = result;
    test:assertEquals(folderListing.documents.length(), 0, msg = "Expected no documents for an empty folder");
    test:assertTrue(folderListing.nextPageToken is (), msg = "Expected no next page token for an empty folder");
}

# Paging through a folder with more documents than fit on one page must return a token the caller
# can use to fetch the next page, and the final page must not carry a token.
@test:Config {}
function testListFolderPagesThroughMultiplePages() returns error? {
    s3:S3Object firstPageObject = {
        key: string `${TEST_TENANT_ID}/invoices/one.pdf`,
        size: 100,
        lastModified: "2026-09-01T00:00:00Z",
        eTag: "etag-one"
    };
    s3:ListObjectsResponse firstPageListing = {
        objects: [firstPageObject],
        count: 1,
        isTruncated: true,
        nextContinuationToken: "page-2-token"
    };
    s3:S3Object secondPageObject = {
        key: string `${TEST_TENANT_ID}/invoices/two.pdf`,
        size: 200,
        lastModified: "2026-09-02T00:00:00Z",
        eTag: "etag-two"
    };
    s3:ListObjectsResponse secondPageListing = {
        objects: [secondPageObject],
        count: 1,
        isTruncated: false
    };
    test:prepare(s3Client).when("listObjects").thenReturnSequence(firstPageListing, secondPageListing);
    test:prepare(s3Client).when("createPresignedUrl").thenReturn("https://example-bucket.s3.amazonaws.com/presigned-url");

    FolderListing|http:BadRequest|http:InternalServerError firstPageResult =
        handleListFolder(TEST_TENANT_ID, "invoices", 1, ());
    if firstPageResult !is FolderListing {
        test:assertFail(msg = "Expected a folder listing response for the first page");
    }
    FolderListing firstPage = firstPageResult;
    test:assertEquals(firstPage.documents.length(), 1, msg = "Expected exactly one document on the first page");
    test:assertEquals(firstPage.documents[0].name, "one.pdf", msg = "Expected the first document's name to exclude the folder prefix");
    string? firstPageToken = firstPage.nextPageToken;
    if firstPageToken is () {
        test:assertFail(msg = "Expected a next page token since more documents remain");
    }
    test:assertEquals(firstPageToken, "page-2-token", msg = "Expected the next page token returned by storage");

    FolderListing|http:BadRequest|http:InternalServerError secondPageResult =
        handleListFolder(TEST_TENANT_ID, "invoices", 1, firstPageToken);
    if secondPageResult !is FolderListing {
        test:assertFail(msg = "Expected a folder listing response for the second page");
    }
    FolderListing secondPage = secondPageResult;
    test:assertEquals(secondPage.documents.length(), 1, msg = "Expected exactly one document on the second page");
    test:assertEquals(secondPage.documents[0].name, "two.pdf", msg = "Expected the second document's name to exclude the folder prefix");
    test:assertTrue(secondPage.nextPageToken is (), msg = "Expected no next page token on the final page");
}
