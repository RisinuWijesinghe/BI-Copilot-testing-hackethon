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
