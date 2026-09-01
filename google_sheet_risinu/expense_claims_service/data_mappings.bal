import ballerinax/googleapis.sheets;

# Maps an expense claim to the row values appended to the Google Sheet.
#
# + claim - the validated expense claim
# + return - the ordered row values: date, category, description, amount
function mapClaimToRowValues(ExpenseClaim claim) returns (int|string|decimal|boolean|float)[] => [
    claim.date,
    claim.category,
    claim.description,
    claim.amount
];

# Builds the A1 range referring to the configured sheet.
#
# + return - the `sheets:A1Range` pointing to the configured sheet
function buildTargetRange() returns sheets:A1Range => {
    sheetName
};

# Builds the A1 notation for the data rows of the configured sheet, skipping the header row.
#
# + return - the A1 notation string covering columns A to D, starting from row 2
function buildDataRangeNotation() returns string => "A2:D";

# Represents a single data row read from the sheet, already parsed into a category and an amount.
type SheetRowEntry record {|
    string category;
    decimal amount;
|};

# Parses a raw row of sheet values into a `SheetRowEntry`.
# A row is considered unreadable (and should be skipped) if it does not have both a category
# (column B) and a numeric amount (column D).
#
# + rowValues - the raw values of a single row, as returned by the Sheets API
# + return - the parsed row entry, or `()` if the row is blank/malformed and must be skipped
function parseSheetRow((int|string|decimal)[] rowValues) returns SheetRowEntry? {
    // Expected column order: date(0), category(1), description(2), amount(3).
    if rowValues.length() < 4 {
        return ();
    }

    int|string|decimal categoryValue = rowValues[1];
    if !(categoryValue is string) {
        return ();
    }

    string category = categoryValue.trim();
    if category.length() == 0 {
        return ();
    }

    int|string|decimal amountValue = rowValues[3];
    decimal? amount = ();
    if amountValue is decimal {
        amount = amountValue;
    } else if amountValue is int {
        amount = <decimal>amountValue;
    } else if amountValue is string {
        string trimmedAmount = amountValue.trim();
        decimal|error parsedAmount = decimal:fromString(trimmedAmount);
        if parsedAmount is decimal {
            amount = parsedAmount;
        }
    }

    if amount is () {
        return ();
    }

    return {category, amount};
}

// Label used for the grand total line at the bottom of the snapshot.
final string grandTotalLabel = "Grand Total";

# Builds the snapshot lines (one per category, plus a grand total line) from a claims summary.
#
# + summary - the aggregated claims summary for the current month
# + return - the ordered snapshot lines, category lines first, grand total last
function buildSnapshotLines(ClaimsSummary summary) returns SnapshotLine[] {
    SnapshotLine[] lines = [];
    foreach string category in allowedCategories {
        decimal categoryTotal = summary.totalsByCategory.get(category);
        lines.push({label: category, total: categoryTotal});
    }
    lines.push({label: grandTotalLabel, total: summary.overallTotal});
    return lines;
}

# Maps snapshot lines to the row values written to the snapshot tab, including a header row.
#
# + lines - the snapshot lines to write
# + return - the rows to write, starting with a header row
function mapSnapshotLinesToRows(SnapshotLine[] lines) returns (int|string|decimal)[][] {
    (int|string|decimal)[][] rows = [["Category", "Total"]];
    foreach SnapshotLine line in lines {
        rows.push([line.label, line.total]);
    }
    return rows;
}
