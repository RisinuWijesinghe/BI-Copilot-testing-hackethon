import ballerina/http;
import ballerina/log;
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

        LocatedStockRow? locatedRow = locateStockRow(rowsValuesResult, sku, headerRowCount);
        if locatedRow is () {
            return <http:NotFound>{
                body: {message: string `sku '${sku}' was not found`}
            };
        }

        return mapToStockLevel(locatedRow);
    }

    # Applies a stock movement to a single SKU: a positive quantity records a delivery in, a
    # negative quantity records goods going out. The matching row's quantity on hand is updated
    # in place; nothing is written if the movement is rejected or the update fails.
    #
    # + sku - the SKU to apply the movement to
    # + movement - the movement to apply
    # + return - the quantity before and after the movement, a rejection if the SKU or quantity
    # is invalid, a not-found if the SKU is not in the sheet, a conflict if the movement would
    # take stock below zero, or a generic failure message if the update could not be written
    resource function post [string sku]/movements(@http:Payload StockMovement movement)
            returns MovementResult|http:BadRequest|http:NotFound|http:Conflict|http:InternalServerError {
        ValidationErrorDetail? skuValidationError = validateSku(sku);
        if skuValidationError is ValidationErrorDetail {
            log:printWarn("rejected stock movement: invalid sku", sku = sku);
            return <http:BadRequest>{
                body: {message: skuValidationError.message}
            };
        }

        ValidationErrorDetail? quantityValidationError = validateMovementQuantity(movement.quantityChange);
        if quantityValidationError is ValidationErrorDetail {
            log:printWarn("rejected stock movement: invalid quantity", sku = sku, quantityChange = movement.quantityChange);
            return <http:BadRequest>{
                body: {message: quantityValidationError.message}
            };
        }

        (int|string|decimal)[][]|http:InternalServerError rowsValuesResult = readDataRows();
        if rowsValuesResult is http:InternalServerError {
            log:printError("stock movement failed: could not read the sheet", sku = sku);
            return rowsValuesResult;
        }

        LocatedStockRow? locatedRow = locateStockRow(rowsValuesResult, sku, headerRowCount);
        if locatedRow is () {
            log:printWarn("rejected stock movement: sku not found", sku = sku);
            return <http:NotFound>{
                body: {message: string `sku '${sku}' was not found`}
            };
        }

        decimal previousQuantity = locatedRow.quantityOnHand;
        decimal newQuantity = previousQuantity + movement.quantityChange;
        if newQuantity < 0d {
            log:printWarn("rejected stock movement: insufficient stock", sku = sku,
                    quantityChange = movement.quantityChange, availableQuantity = previousQuantity);
            return <http:Conflict>{
                body: {
                    message: "movement rejected: insufficient stock available",
                    availableQuantity: previousQuantity
                }
            };
        }

        string quantityCellNotation = buildQuantityCellNotation(locatedRow.rowPosition);
        error? updateResult = sheetsClient->setCell(spreadsheetId, sheetName, quantityCellNotation, newQuantity);
        if updateResult is error {
            log:printError("stock movement failed: could not write the update", updateResult, sku = sku);
            return <http:InternalServerError>{
                body: {message: "could not record the stock movement, please retry"}
            };
        }

        log:printInfo("stock movement applied", sku = sku, quantityChange = movement.quantityChange,
                previousQuantity = previousQuantity, newQuantity = newQuantity);

        return {
            sku: locatedRow.sku,
            previousQuantity,
            newQuantity,
            reorderThreshold: locatedRow.reorderThreshold,
            lowStock: newQuantity <= locatedRow.reorderThreshold
        };
    }
}
