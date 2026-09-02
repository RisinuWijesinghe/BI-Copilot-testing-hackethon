import ballerina/data.csv;

# Parses the raw CSV content of a sales report into an array of rows.
#
# + csvContent - the raw CSV text content
# + return - the parsed report rows, or an error if the content is not valid CSV
function parseReportCsv(string csvContent) returns SalesReportRow[]|error => csv:parseString(csvContent);
