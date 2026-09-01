import ballerina/lang.regexp;

// A SKU must be a short alphanumeric code (letters, digits, hyphens, underscores). This keeps
// obviously malformed input from ever reaching the sheet.
final regexp:RegExp skuPattern = re `^[A-Za-z0-9_-]{1,64}$`;

# Validates an incoming SKU before any sheet access is attempted.
#
# + sku - the SKU submitted by the caller
# + return - `()` when the SKU is well-formed, otherwise a `ValidationErrorDetail` describing the problem
function validateSku(string sku) returns ValidationErrorDetail? {
    string trimmedSku = sku.trim();
    if trimmedSku.length() == 0 {
        return {message: "sku is required"};
    }

    if !skuPattern.isFullMatch(trimmedSku) {
        return {message: "sku is malformed: only letters, digits, hyphens and underscores are allowed"};
    }

    return ();
}

# Parses a raw row of sheet values into a `SheetRowEntry`.
# A row is considered unreadable (and should be skipped) if it does not have a SKU (column A),
# a product name (column B), a numeric quantity on hand (column C) and a numeric reorder
# threshold (column D).
#
# + rowValues - the raw values of a single row, as returned by the Sheets API
# + return - the parsed row entry, or `()` if the row is blank/malformed and must be skipped
function parseSheetRow((int|string|decimal)[] rowValues) returns SheetRowEntry? {
    // Expected column order: sku(0), productName(1), quantityOnHand(2), reorderThreshold(3).
    if rowValues.length() < 4 {
        return ();
    }

    int|string|decimal skuValue = rowValues[0];
    if !(skuValue is string) {
        return ();
    }
    string sku = skuValue.trim();
    if sku.length() == 0 {
        return ();
    }

    int|string|decimal productNameValue = rowValues[1];
    if !(productNameValue is string) {
        return ();
    }
    string productName = productNameValue.trim();
    if productName.length() == 0 {
        return ();
    }

    decimal? quantityOnHand = toDecimal(rowValues[2]);
    if quantityOnHand is () {
        return ();
    }

    decimal? reorderThreshold = toDecimal(rowValues[3]);
    if reorderThreshold is () {
        return ();
    }

    return {sku, productName, quantityOnHand, reorderThreshold};
}

# Converts a raw sheet cell value into a `decimal`, if possible.
#
# + cellValue - the raw cell value
# + return - the parsed decimal, or `()` if the value is not numeric
function toDecimal(int|string|decimal cellValue) returns decimal? {
    if cellValue is decimal {
        return cellValue;
    }
    if cellValue is int {
        return <decimal>cellValue;
    }
    string trimmedValue = cellValue.trim();
    decimal|error parsedValue = decimal:fromString(trimmedValue);
    if parsedValue is decimal {
        return parsedValue;
    }
    return ();
}

# Searches the given rows for the one matching the requested SKU (case-insensitive), keeping
# track of its absolute row position in the sheet so a caller can write an update back to it.
# This is the single lookup used both to read stock levels and to locate the row for a movement.
#
# + rowsValues - the raw data rows read from the sheet, excluding the header row
# + sku - the SKU to locate
# + headerRowCount - the number of header rows preceding `rowsValues` in the sheet
# + return - the matching row, or `()` if no row matches the SKU
function locateStockRow((int|string|decimal)[][] rowsValues, string sku, int headerRowCount) returns LocatedStockRow? {
    string normalizedSku = sku.trim().toLowerAscii();

    int rowOffset = 0;
    foreach (int|string|decimal)[] rowValues in rowsValues {
        rowOffset += 1;
        SheetRowEntry? entry = parseSheetRow(rowValues);
        if entry is () {
            continue;
        }

        if entry.sku.toLowerAscii() != normalizedSku {
            continue;
        }

        return {
            sku: entry.sku,
            productName: entry.productName,
            quantityOnHand: entry.quantityOnHand,
            reorderThreshold: entry.reorderThreshold,
            rowPosition: headerRowCount + rowOffset
        };
    }

    return ();
}

# Maps a located stock row into the public `StockLevel` representation.
#
# + locatedRow - the row located via `locateStockRow`
# + return - the stock level for the row
function mapToStockLevel(LocatedStockRow locatedRow) returns StockLevel => {
    sku: locatedRow.sku,
    productName: locatedRow.productName,
    quantityOnHand: locatedRow.quantityOnHand,
    reorderThreshold: locatedRow.reorderThreshold,
    lowStock: locatedRow.quantityOnHand <= locatedRow.reorderThreshold
};

# Validates an incoming stock movement quantity before any sheet access is attempted.
#
# + quantityChange - the movement quantity submitted by the caller
# + return - `()` when the quantity is valid, otherwise a `ValidationErrorDetail` describing the problem
function validateMovementQuantity(decimal quantityChange) returns ValidationErrorDetail? {
    if quantityChange == 0d {
        return {message: "quantityChange must not be zero"};
    }
    return ();
}

# Finds SKUs that appear more than once in a bulk movement request (case-insensitive), so the
# whole request can be rejected outright rather than applying some lines against the same row
# more than once.
#
# + movements - the requested movement lines
# + return - the set of duplicated SKUs (as originally submitted), empty if none are duplicated
function findDuplicateSkus(SkuMovement[] movements) returns string[] {
    map<int> occurrenceCounts = {};
    string[] duplicates = [];

    foreach SkuMovement movement in movements {
        string normalizedSku = movement.sku.trim().toLowerAscii();
        int currentCount = occurrenceCounts[normalizedSku] ?: 0;
        occurrenceCounts[normalizedSku] = currentCount + 1;
        if currentCount == 1 {
            // Second time we see this SKU: record it once, keyed by its first-seen original casing.
            duplicates.push(movement.sku);
        }
    }

    return duplicates;
}

# Validates that a SKU is eligible to be retired: it must currently have no stock on hand.
#
# + locatedRow - the row located for the SKU being retired
# + return - `()` when the SKU can be retired, otherwise a `StockRemainingDetail` describing why not
function validateRetireEligibility(LocatedStockRow locatedRow) returns StockRemainingDetail? {
    if locatedRow.quantityOnHand > 0d {
        return {
            message: "sku cannot be retired while stock remains on hand",
            quantityOnHand: locatedRow.quantityOnHand
        };
    }
    return ();
}
