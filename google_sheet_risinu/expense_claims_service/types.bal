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

# Spend summary across all categories for the current month.
public type ClaimsSummary record {|
    map<decimal> totalsByCategory;
    decimal overallTotal;
    int skippedRowCount;
|};

# Spend summary for a single category for the current month.
public type CategorySummary record {|
    string category;
    decimal total;
    int skippedRowCount;
|};

# A single line of a frozen snapshot: either a category total or the grand total line.
public type SnapshotLine record {|
    string label;
    decimal total;
|};

# Confirmation returned after a month-end snapshot has been written.
public type SnapshotResult record {|
    string message;
    SnapshotLine[] lines;
|};
