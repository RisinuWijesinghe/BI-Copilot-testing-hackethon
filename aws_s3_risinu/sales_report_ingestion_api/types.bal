// Represents a single row of a sales report, parsed from CSV.
public type SalesReportRow record {|
    string...;
|};

# Metadata about a stored sales report.
public type ReportSummary record {|
    string date;
    int sizeInBytes;
    string lastModified;
|};

# Response payload returned when listing the reports currently held in the bucket.
public type ReportListResponse record {|
    ReportSummary[] reports;
|};

# Response payload returned when fetching a single report as JSON.
public type ReportContentResponse record {|
    string date;
    SalesReportRow[] rows;
|};

# A generic, customer-safe error payload. Never includes AWS error codes, bucket names, or key material.
public type ErrorPayload record {|
    string message;
|};
