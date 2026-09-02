import ballerina/http;
import ballerina/log;
import ballerinax/aws.s3;

const string GENERIC_STORAGE_ERROR_MESSAGE = "The report storage service is currently unavailable. Please try again later.";
const string INVALID_PAYLOAD_MESSAGE = "The uploaded report could not be read as CSV text.";

# Builds the S3 object key for a given report date.
#
# + reportDate - the report date, e.g. 2026-09-01
# + return - the corresponding S3 object key
function buildReportObjectKey(string reportDate) returns string => string `${reportDate}.csv`;

# Handles uploading a CSV report for the given date.
#
# + reportDate - the report date
# + request - the inbound request carrying the CSV payload
# + return - the created report summary, a bad request, or a generic server error
function handleUploadReport(string reportDate, http:Request request) returns ReportSummary|http:BadRequest|http:InternalServerError {
    string|http:ClientError csvContent = request.getTextPayload();
    if csvContent is http:ClientError {
        log:printError("Failed to read the report payload as text", 'error = csvContent, reportDate = reportDate);
        return <http:BadRequest>{body: {message: INVALID_PAYLOAD_MESSAGE}};
    }

    string objectKey = buildReportObjectKey(reportDate);
    s3:Error? putResult = s3Client->putObject(bucketName, objectKey, csvContent, contentType = "text/csv", fileFormat = s3:CSV);
    if putResult is s3:Error {
        log:printError("Failed to upload report to S3", 'error = putResult, objectKey = objectKey);
        return <http:InternalServerError>{body: {message: GENERIC_STORAGE_ERROR_MESSAGE}};
    }

    return {
        date: reportDate,
        sizeInBytes: csvContent.toBytes().length(),
        lastModified: ""
    };
}

# Handles listing the sales reports currently held in the bucket.
#
# + return - the list of report summaries, or a generic server error
function handleListReports() returns ReportListResponse|http:InternalServerError {
    s3:ListObjectsResponse|s3:Error listResult = s3Client->listObjects(bucketName);
    if listResult is s3:Error {
        log:printError("Failed to list reports from S3", 'error = listResult);
        return <http:InternalServerError>{body: {message: GENERIC_STORAGE_ERROR_MESSAGE}};
    }

    ReportSummary[] reports = from s3:S3Object s3Object in listResult.objects
        select {
            date: extractReportDate(s3Object.key),
            sizeInBytes: s3Object.size,
            lastModified: s3Object.lastModified
        };

    return {reports};
}

# Extracts the report date from an S3 object key by stripping the .csv suffix.
#
# + objectKey - the S3 object key
# + return - the report date portion of the key
function extractReportDate(string objectKey) returns string {
    if objectKey.endsWith(".csv") {
        return objectKey.substring(0, objectKey.length() - 4);
    }
    return objectKey;
}

# Handles fetching a single sales report and converting its content to JSON.
#
# + reportDate - the report date
# + return - the report content as JSON, a not found, or a generic server error
function handleGetReport(string reportDate) returns ReportContentResponse|http:NotFound|http:InternalServerError {
    string objectKey = buildReportObjectKey(reportDate);

    boolean|s3:Error existsResult = s3Client->doesObjectExist(bucketName, objectKey);
    if existsResult is s3:Error {
        log:printError("Failed to check report existence in S3", 'error = existsResult, objectKey = objectKey);
        return <http:InternalServerError>{body: {message: GENERIC_STORAGE_ERROR_MESSAGE}};
    }
    if !existsResult {
        return <http:NotFound>{body: {message: string `No report found for date ${reportDate}.`}};
    }

    string|s3:Error getResult = s3Client->getObject(bucketName, objectKey, targetType = string);
    if getResult is s3:Error {
        log:printError("Failed to download report from S3", 'error = getResult, objectKey = objectKey);
        return <http:InternalServerError>{body: {message: GENERIC_STORAGE_ERROR_MESSAGE}};
    }

    SalesReportRow[]|error rows = parseReportCsv(getResult);
    if rows is error {
        log:printError("Failed to parse report CSV content", 'error = rows, objectKey = objectKey);
        return <http:InternalServerError>{body: {message: GENERIC_STORAGE_ERROR_MESSAGE}};
    }

    return {
        date: reportDate,
        rows
    };
}
