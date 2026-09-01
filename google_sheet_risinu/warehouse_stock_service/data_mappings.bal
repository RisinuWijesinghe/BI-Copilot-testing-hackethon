// Builds the A1 notation for the data rows of the configured sheet, skipping the header row.
final string dataRangeNotation = "A2:D";

// Number of header rows preceding the data range above; used to translate a data row's relative
// offset into its absolute row position in the sheet.
final int headerRowCount = 1;

// Column letter holding the quantity-on-hand value for a stock row.
final string quantityColumnLetter = "C";

# Builds the A1 notation for the quantity-on-hand cell of a specific row.
#
# + rowPosition - the absolute row position in the sheet
# + return - the A1 notation for the quantity cell of that row
function buildQuantityCellNotation(int rowPosition) returns string => quantityColumnLetter + rowPosition.toString();
