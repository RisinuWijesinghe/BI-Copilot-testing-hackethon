// Fixed set of allowed expense categories.
public type ExpenseCategory "Travel"|"Meals"|"Office"|"Other";

# Represents an incoming expense claim submission.
public type ExpenseClaim record {|
    string date;
    string category;
    string description;
    decimal amount;
|};

# Confirmation returned after a claim has been successfully recorded.
public type ClaimConfirmation record {|
    string message;
    int rowNumber;
|};

# Represents a validation failure detected before anything is written.
public type ValidationErrorDetail record {|
    string message;
|};
