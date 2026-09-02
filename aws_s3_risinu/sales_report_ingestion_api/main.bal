import ballerina/http;

service /reports on new http:Listener(servicePort) {

    # Uploads a daily sales report CSV for the given date.
    #
    # + reportDate - the report date, e.g. 2026-09-01
    # + request - the inbound request carrying the CSV payload
    # + return - the created report summary, a bad request if the payload is invalid,
    # or a generic server error if the storage layer fails
    resource function put [string reportDate](http:Request request) returns ReportSummary|http:BadRequest|http:InternalServerError {
        return handleUploadReport(reportDate, request);
    }

    # Lists the sales reports currently held in the bucket.
    #
    # + return - the list of report summaries, or a generic server error if the storage layer fails
    resource function get .() returns ReportListResponse|http:InternalServerError {
        return handleListReports();
    }

    # Fetches a single sales report and returns its content as JSON.
    #
    # + reportDate - the report date, e.g. 2026-09-01
    # + return - the report content as JSON, a not found if the report does not exist,
    # or a generic server error if the storage layer fails
    resource function get [string reportDate]() returns ReportContentResponse|http:NotFound|http:InternalServerError {
        return handleGetReport(reportDate);
    }
}
