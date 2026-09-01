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
