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

# Applies a single stock movement against an already-read snapshot of the sheet's data rows.
# This is the one place that locates a row, enforces the below-zero guard and writes the update,
# so both the single-movement and bulk-movement endpoints behave identically for a given line.
#
# + sku - the SKU to apply the movement to
# + quantityChange - the movement quantity; positive for a delivery in, negative for goods going out
# + rowsValues - the sheet's data rows, read once up front
# + return - the outcome of this one line: applied, not found, insufficient stock, or failed to write
function applyMovementToRow(string sku, decimal quantityChange, (int|string|decimal)[][] rowsValues)
        returns MovementOutcome {
    LocatedStockRow? locatedRow = locateStockRow(rowsValues, sku, headerRowCount);
    if locatedRow is () {
        log:printWarn("rejected stock movement: sku not found", sku = sku);
        return {sku, status: "NOT_FOUND", message: string `sku '${sku}' was not found`};
    }

    decimal previousQuantity = locatedRow.quantityOnHand;
    decimal newQuantity = previousQuantity + quantityChange;
    if newQuantity < 0d {
        log:printWarn("rejected stock movement: insufficient stock", sku = sku,
                quantityChange = quantityChange, availableQuantity = previousQuantity);
        return {
            sku,
            status: "INSUFFICIENT_STOCK",
            message: "movement rejected: insufficient stock available",
            previousQuantity
        };
    }

    string quantityCellNotation = buildQuantityCellNotation(locatedRow.rowPosition);
    error? updateResult = sheetsClient->setCell(spreadsheetId, sheetName, quantityCellNotation, newQuantity);
    if updateResult is error {
        log:printError("stock movement failed: could not write the update", updateResult, sku = sku);
        return {sku, status: "FAILED", message: "could not record the stock movement, please retry"};
    }

    log:printInfo("stock movement applied", sku = sku, quantityChange = quantityChange,
            previousQuantity = previousQuantity, newQuantity = newQuantity);

    return {
        sku: locatedRow.sku,
        status: "APPLIED",
        message: "movement applied",
        previousQuantity,
        newQuantity,
        reorderThreshold: locatedRow.reorderThreshold,
        lowStock: newQuantity <= locatedRow.reorderThreshold
    };
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

        MovementOutcome outcome = applyMovementToRow(sku, movement.quantityChange, rowsValuesResult);
        if outcome.status == "NOT_FOUND" {
            return <http:NotFound>{
                body: {message: outcome.message}
            };
        }
        if outcome.status == "INSUFFICIENT_STOCK" {
            return <http:Conflict>{
                body: {
                    message: outcome.message,
                    availableQuantity: outcome.previousQuantity
                }
            };
        }
        if outcome.status == "FAILED" {
            return <http:InternalServerError>{
                body: {message: outcome.message}
            };
        }

        decimal previousQuantity = <decimal>outcome.previousQuantity;
        decimal newQuantity = <decimal>outcome.newQuantity;
        decimal reorderThreshold = <decimal>outcome.reorderThreshold;
        boolean lowStock = <boolean>outcome.lowStock;
        return {
            sku: outcome.sku,
            previousQuantity,
            newQuantity,
            reorderThreshold,
            lowStock
        };
    }

    # Applies a batch of stock movements in a single request, one per SKU. Every line is
    # attempted independently against a single read of the sheet, so one bad line does not block
    # the others; the response lists a per-SKU outcome and an `allApplied` flag that is `false`
    # whenever any line did not succeed. The same SKU appearing more than once in the request is
    # rejected outright, without applying any line.
    #
    # + movements - the movement lines to apply, one per SKU
    # + return - the per-SKU outcomes, a rejection if the request itself is malformed (e.g.
    # duplicate SKUs), or a generic failure message if the sheet could not be read at all
    resource function post movements(@http:Payload SkuMovement[] movements)
            returns BulkMovementResult|http:BadRequest|http:InternalServerError {
        if movements.length() == 0 {
            log:printWarn("rejected bulk stock movement: empty request");
            return <http:BadRequest>{
                body: {message: "at least one movement is required"}
            };
        }

        string[] duplicateSkus = findDuplicateSkus(movements);
        if duplicateSkus.length() > 0 {
            log:printWarn("rejected bulk stock movement: duplicate skus", duplicateSkus = duplicateSkus);
            return <http:BadRequest>{
                body: {
                    message: string `duplicate sku(s) in request: ${string:'join(", ", ...duplicateSkus)}`
                }
            };
        }

        (int|string|decimal)[][]|http:InternalServerError rowsValuesResult = readDataRows();
        if rowsValuesResult is http:InternalServerError {
            log:printError("bulk stock movement failed: could not read the sheet");
            return rowsValuesResult;
        }

        MovementOutcome[] results = [];
        boolean allApplied = true;

        foreach SkuMovement lineItem in movements {
            ValidationErrorDetail? skuValidationError = validateSku(lineItem.sku);
            if skuValidationError is ValidationErrorDetail {
                log:printWarn("rejected stock movement line: invalid sku", sku = lineItem.sku);
                results.push({sku: lineItem.sku, status: "INVALID", message: skuValidationError.message});
                allApplied = false;
                continue;
            }

            ValidationErrorDetail? quantityValidationError = validateMovementQuantity(lineItem.quantityChange);
            if quantityValidationError is ValidationErrorDetail {
                log:printWarn("rejected stock movement line: invalid quantity", sku = lineItem.sku,
                        quantityChange = lineItem.quantityChange);
                results.push({sku: lineItem.sku, status: "INVALID", message: quantityValidationError.message});
                allApplied = false;
                continue;
            }

            MovementOutcome outcome = applyMovementToRow(lineItem.sku, lineItem.quantityChange, rowsValuesResult);
            if outcome.status != "APPLIED" {
                allApplied = false;
            }
            results.push(outcome);
        }

        return {allApplied, results};
    }

    # Retires a SKU by removing its row from the sheet entirely. Refused while the SKU still has
    # stock on hand, so a retirement can never silently discard remaining inventory.
    #
    # + sku - the SKU to retire
    # + return - a confirmation, a rejection if the SKU is malformed, a not-found if the SKU is
    # not in the sheet, a conflict if stock remains on hand, or a generic failure message
    resource function delete [string sku]() returns RetireResult|http:BadRequest|http:NotFound|http:Conflict|http:InternalServerError {
        ValidationErrorDetail? skuValidationError = validateSku(sku);
        if skuValidationError is ValidationErrorDetail {
            log:printWarn("rejected sku retirement: invalid sku", sku = sku);
            return <http:BadRequest>{
                body: {message: skuValidationError.message}
            };
        }

        (int|string|decimal)[][]|http:InternalServerError rowsValuesResult = readDataRows();
        if rowsValuesResult is http:InternalServerError {
            log:printError("sku retirement failed: could not read the sheet", sku = sku);
            return rowsValuesResult;
        }

        LocatedStockRow? locatedRow = locateStockRow(rowsValuesResult, sku, headerRowCount);
        if locatedRow is () {
            log:printWarn("rejected sku retirement: sku not found", sku = sku);
            return <http:NotFound>{
                body: {message: string `sku '${sku}' was not found`}
            };
        }

        StockRemainingDetail? stockRemainingError = validateRetireEligibility(locatedRow);
        if stockRemainingError is StockRemainingDetail {
            log:printWarn("rejected sku retirement: stock remains on hand", sku = sku,
                    quantityOnHand = locatedRow.quantityOnHand);
            return <http:Conflict>{
                body: {
                    message: stockRemainingError.message,
                    quantityOnHand: stockRemainingError.quantityOnHand
                }
            };
        }

        error? deleteResult = sheetsClient->deleteRowsBySheetName(spreadsheetId, sheetName, locatedRow.rowPosition, 1);
        if deleteResult is error {
            log:printError("sku retirement failed: could not delete the row", deleteResult, sku = sku);
            return <http:InternalServerError>{
                body: {message: "could not retire the sku, please retry"}
            };
        }

        log:printInfo("sku retired", sku = sku);
        return {sku: locatedRow.sku, message: "sku retired"};
    }
}
