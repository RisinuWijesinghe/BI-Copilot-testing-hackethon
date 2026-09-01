// Fixed list of categories accepted for an expense claim.
final string[] & readonly allowedCategories = ["Travel", "Meals", "Office", "Other"];

# Validates an incoming expense claim.
#
# + claim - the expense claim submitted by the caller
# + return - `()` when the claim is valid, otherwise a `ValidationErrorDetail` describing the problem
function validateClaim(ExpenseClaim claim) returns ValidationErrorDetail? {
    string date = claim.date.trim();
    string category = claim.category.trim();
    string description = claim.description.trim();

    if date.length() == 0 {
        return {message: "date is required"};
    }

    if category.length() == 0 {
        return {message: "category is required"};
    }

    if description.length() == 0 {
        return {message: "description is required"};
    }

    if claim.amount <= 0d {
        return {message: "amount must be a positive number"};
    }

    boolean isAllowedCategory = allowedCategories.indexOf(category) is int;
    if !isAllowedCategory {
        return {message: string `category must be one of: ${string:'join(", ", ...allowedCategories)}`};
    }

    return ();
}

# Validates that the given category is one of the fixed set of accepted categories.
#
# + category - the category to validate
# + return - `()` when the category is valid, otherwise a `ValidationErrorDetail` describing the problem
function validateCategory(string category) returns ValidationErrorDetail? {
    boolean isAllowedCategory = allowedCategories.indexOf(category) is int;
    if !isAllowedCategory {
        return {message: string `category must be one of: ${string:'join(", ", ...allowedCategories)}`};
    }
    return ();
}

# Aggregates the raw rows read from the sheet into totals per category, initializing every known
# category to zero so that categories with no claims are still represented.
#
# + rowsValues - the raw data rows read from the sheet, excluding the header row
# + return - a record with the totals per category, the overall total and the count of skipped rows
function aggregateClaimsSummary((int|string|decimal)[][] rowsValues) returns ClaimsSummary {
    map<decimal> totalsByCategory = {};
    foreach string category in allowedCategories {
        totalsByCategory[category] = 0d;
    }

    decimal overallTotal = 0d;
    int skippedRowCount = 0;

    foreach (int|string|decimal)[] rowValues in rowsValues {
        SheetRowEntry? entry = parseSheetRow(rowValues);
        if entry is () {
            skippedRowCount += 1;
            continue;
        }

        if !(allowedCategories.indexOf(entry.category) is int) {
            skippedRowCount += 1;
            continue;
        }

        decimal existingTotal = totalsByCategory.get(entry.category);
        totalsByCategory[entry.category] = existingTotal + entry.amount;
        overallTotal += entry.amount;
    }

    return {totalsByCategory, overallTotal, skippedRowCount};
}

# Aggregates the raw rows read from the sheet into a total for a single category.
#
# + rowsValues - the raw data rows read from the sheet, excluding the header row
# + category - the category to total
# + return - a record with the total for the category and the count of skipped rows
function aggregateCategorySummary((int|string|decimal)[][] rowsValues, string category) returns CategorySummary {
    decimal total = 0d;
    int skippedRowCount = 0;

    foreach (int|string|decimal)[] rowValues in rowsValues {
        SheetRowEntry? entry = parseSheetRow(rowValues);
        if entry is () {
            skippedRowCount += 1;
            continue;
        }

        if entry.category == category {
            total += entry.amount;
        }
    }

    return {category, total, skippedRowCount};
}
