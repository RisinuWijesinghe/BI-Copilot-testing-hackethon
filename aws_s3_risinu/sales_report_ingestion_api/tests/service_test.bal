import ballerina/http;
import ballerina/test;
import ballerinax/aws.s3;

const string TEST_REPORT_DATE = "2026-09-01";

# A report that was never uploaded must come back as a clean not found, not a server error.
@test:Config {}
function testGetReportSummaryForMissingReport() returns error? {
    test:prepare(s3Client).when("doesObjectExist").thenReturn(false);

    ReportSummaryResponse|http:NotFound|http:PayloadTooLarge|http:InternalServerError result =
        handleGetReportSummary(TEST_REPORT_DATE);

    test:assertTrue(result is http:NotFound, msg = "Expected a not found response for a report that was never uploaded");
}

# A report that exceeds the configured size limit must be rejected before it is downloaded,
# with a clear too-large rejection distinct from not found.
@test:Config {}
function testGetReportSummaryForOversizedReport() returns error? {
    test:prepare(s3Client).when("doesObjectExist").thenReturn(true);

    s3:ObjectMetadata oversizedMetadata = {
        key: buildReportObjectKey(TEST_REPORT_DATE),
        contentLength: maxReportSizeInBytes + 1,
        eTag: "test-etag",
        lastModified: "2026-09-01T00:00:00Z"
    };
    test:prepare(s3Client).when("getObjectMetadata").thenReturn(oversizedMetadata);

    ReportSummaryResponse|http:NotFound|http:PayloadTooLarge|http:InternalServerError result =
        handleGetReportSummary(TEST_REPORT_DATE);

    test:assertTrue(result is http:PayloadTooLarge, msg = "Expected a payload too large response for an oversized report");
}

# Rows with missing or unparseable revenue values must be dropped rather than failing the whole
# request, and the response must report how many rows were skipped.
@test:Config {}
function testGetReportSummaryWithSomeBadRows() returns error? {
    test:prepare(s3Client).when("doesObjectExist").thenReturn(true);

    s3:ObjectMetadata metadata = {
        key: buildReportObjectKey(TEST_REPORT_DATE),
        contentLength: 200,
        eTag: "test-etag",
        lastModified: "2026-09-01T00:00:00Z"
    };
    test:prepare(s3Client).when("getObjectMetadata").thenReturn(metadata);

    string csvContent = string `product,revenue
Widget,100
Gadget,not-a-number
Widget,50
Gizmo,
`;
    test:prepare(s3Client).when("getObject").thenReturn(csvContent);
    test:prepare(s3Client).when("putObject").thenReturn(());

    ReportSummaryResponse|http:NotFound|http:PayloadTooLarge|http:InternalServerError result =
        handleGetReportSummary(TEST_REPORT_DATE);

    if result !is ReportSummaryResponse {
        test:assertFail(msg = "Expected a report summary response for a report with some bad rows");
    }

    ReportSummaryResponse summary = result;
    test:assertEquals(summary.rowCount, 2, msg = "Expected only the two valid rows to be counted");
    test:assertEquals(summary.skippedRowCount, 2, msg = "Expected the two bad rows to be reported as skipped");
    test:assertEquals(summary.totalRevenue, 150d, msg = "Expected total revenue to only include valid rows");
    test:assertEquals(summary.bestSellingProduct, "Widget", msg = "Expected Widget to be the best-selling product");
}

# Archiving a report that has already been archived must be safe to call again, reporting that
# fact rather than failing or attempting the move a second time.
@test:Config {}
function testArchiveReportThatIsAlreadyArchived() returns error? {
    test:prepare(s3Client).when("doesObjectExist").thenReturn(true);

    ArchiveResponse|http:NotFound|http:InternalServerError result = handleArchiveReport(TEST_REPORT_DATE);

    if result !is ArchiveResponse {
        test:assertFail(msg = "Expected an archive response for an already-archived report");
    }

    ArchiveResponse archiveResponse = result;
    test:assertEquals(archiveResponse.alreadyArchived, true, msg = "Expected the report to be reported as already archived");
}

# Archiving a report that was never uploaded must behave exactly as the other endpoints do:
# a clean not found rather than a server error.
@test:Config {}
function testArchiveReportForMissingReport() returns error? {
    test:prepare(s3Client).when("doesObjectExist").thenReturnSequence(false, false);

    ArchiveResponse|http:NotFound|http:InternalServerError result = handleArchiveReport(TEST_REPORT_DATE);

    test:assertTrue(result is http:NotFound, msg = "Expected a not found response for a report that was never uploaded");
}

# A successful archive copies the report into the archive area and only then removes the original.
@test:Config {}
function testArchiveReportSucceeds() returns error? {
    test:prepare(s3Client).when("doesObjectExist").thenReturnSequence(false, true);
    test:prepare(s3Client).when("copyObject").thenReturn(());
    test:prepare(s3Client).when("deleteObject").thenReturn(());

    ArchiveResponse|http:NotFound|http:InternalServerError result = handleArchiveReport(TEST_REPORT_DATE);

    if result !is ArchiveResponse {
        test:assertFail(msg = "Expected an archive response for a successful archive");
    }

    ArchiveResponse archiveResponse = result;
    test:assertEquals(archiveResponse.alreadyArchived, false, msg = "Expected a freshly archived report to report alreadyArchived as false");
}

# If the copy succeeds but the cleanup of the original fails, the caller must not be told the
# archive succeeded - a copy already exists, so this must surface as a server error, never a
# success response.
@test:Config {}
function testArchiveReportFailsWhenCleanupFails() returns error? {
    test:prepare(s3Client).when("doesObjectExist").thenReturnSequence(false, true);
    test:prepare(s3Client).when("copyObject").thenReturn(());

    error mockDeleteError = error("SimulatedDeleteFailure", message = "Simulated failure removing the original object");
    test:prepare(s3Client).when("deleteObject").thenReturn(mockDeleteError);

    ArchiveResponse|http:NotFound|http:InternalServerError result = handleArchiveReport(TEST_REPORT_DATE);

    test:assertTrue(result is http:InternalServerError,
            msg = "Expected a generic server error, never a success response, when cleanup of the original fails");
}
