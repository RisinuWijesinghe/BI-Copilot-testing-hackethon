import ballerina/http;
import ballerinax/googleapis.sheets;

# Reads the data rows (excluding the header row) of the configured sheet.
# A sheet that has no data rows yet (headers only, or completely empty) is treated as a valid,
# empty data set rather than an error.
#
# + return - the raw data rows, an empty array when there is no data yet, or a generic failure message
function readDataRows() returns (int|string|decimal)[][]|http:InternalServerError {
    string dataRangeNotation = buildDataRangeNotation();
    sheets:Range|error rangeResult = sheetsClient->getRange(spreadsheetId, sheetName, dataRangeNotation);
    if rangeResult is error {
        string errorMessage = rangeResult.message();
        // The Sheets API returns no `values` field at all when the requested range has no data yet
        // (e.g. the sheet only has a header row). Treat that as a valid, empty data set.
        boolean isEmptyRange = errorMessage.includes("Range not found")
            || errorMessage.includes("exceeds grid limits")
            || errorMessage.includes("values");
        if isEmptyRange {
            return [];
        }
        return <http:InternalServerError>{
            body: {message: "could not read the claims, please retry"}
        };
    }

    return rangeResult.values;
}

service /claims on new http:Listener(8080) {

    # Records a new expense claim as a row in the current month's Google Sheet.
    #
    # + claim - the expense claim submitted by the caller
    # + return - a confirmation with the row the claim landed in, a validation error, or a generic failure message
    resource function post .(@http:Payload ExpenseClaim claim) returns ClaimConfirmation|http:BadRequest|http:InternalServerError {
        ValidationErrorDetail? validationError = validateClaim(claim);
        if validationError is ValidationErrorDetail {
            return <http:BadRequest>{
                body: {message: validationError.message}
            };
        }

        (int|string|decimal|boolean|float)[] rowValues = mapClaimToRowValues(claim);
        sheets:A1Range targetRange = buildTargetRange();

        sheets:ValueRange|error appendResult = sheetsClient->appendValue(spreadsheetId, rowValues, targetRange);
        if appendResult is error {
            return <http:InternalServerError>{
                body: {message: "could not record the claim, please retry"}
            };
        }

        return {
            message: "claim recorded",
            rowNumber: appendResult.rowPosition
        };
    }

    # Returns this month's spend broken down by category, plus an overall total, read live from the sheet.
    #
    # + return - the claims summary, or a generic failure message if the sheet could not be read
    resource function get summary() returns ClaimsSummary|http:InternalServerError {
        (int|string|decimal)[][]|http:InternalServerError rowsValuesResult = readDataRows();
        if rowsValuesResult is http:InternalServerError {
            return rowsValuesResult;
        }

        return aggregateClaimsSummary(rowsValuesResult);
    }

    # Returns this month's spend for a single category, read live from the sheet.
    #
    # + category - the category to report on
    # + return - the category summary, a rejection if the category is not recognized, or a generic failure message
    resource function get summary/[string category]() returns CategorySummary|http:BadRequest|http:InternalServerError {
        ValidationErrorDetail? validationError = validateCategory(category);
        if validationError is ValidationErrorDetail {
            return <http:BadRequest>{
                body: {message: validationError.message}
            };
        }

        (int|string|decimal)[][]|http:InternalServerError rowsValuesResult = readDataRows();
        if rowsValuesResult is http:InternalServerError {
            return rowsValuesResult;
        }

        return aggregateCategorySummary(rowsValuesResult, category);
    }
}
