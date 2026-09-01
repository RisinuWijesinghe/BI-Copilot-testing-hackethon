import ballerina/http;
import ballerinax/googleapis.sheets;

# Reads the data rows (excluding the header row) of the configured stock sheet.
# A sheet that has no data rows yet (headers only, or completely empty) is treated as a valid,
# empty data set rather than an error.
#
# + return - the raw data rows, an empty array when there is no data yet, or a generic failure message
function readDataRows() returns (int|string|decimal)[][]|http:InternalServerError {
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
            body: {message: "could not read the stock levels, please retry"}
        };
    }

    return rangeResult.values;
}

service /stock on new http:Listener(8080) {

    # Looks up the current stock level for a single SKU, read live from the warehouse stock sheet.
    #
    # + sku - the SKU to look up
    # + return - the stock level, a rejection if the SKU is malformed, a not-found if the SKU is
    # not in the sheet, or a generic failure message
    resource function get [string sku]() returns StockLevel|http:BadRequest|http:NotFound|http:InternalServerError {
        ValidationErrorDetail? validationError = validateSku(sku);
        if validationError is ValidationErrorDetail {
            return <http:BadRequest>{
                body: {message: validationError.message}
            };
        }

        (int|string|decimal)[][]|http:InternalServerError rowsValuesResult = readDataRows();
        if rowsValuesResult is http:InternalServerError {
            return rowsValuesResult;
        }

        StockLevel? stockLevel = findStockLevel(rowsValuesResult, sku);
        if stockLevel is () {
            return <http:NotFound>{
                body: {message: string `sku '${sku}' was not found`}
            };
        }

        return stockLevel;
    }
}
