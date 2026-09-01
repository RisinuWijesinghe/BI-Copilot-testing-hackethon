# Stock details for a single SKU, read live from the warehouse stock sheet.
public type StockLevel record {|
    string sku;
    string productName;
    decimal quantityOnHand;
    decimal reorderThreshold;
    boolean lowStock;
|};

# Represents a validation failure detected before the sheet is consulted.
public type ValidationErrorDetail record {|
    string message;
|};

# Represents a single data row read from the sheet, already parsed into its typed columns.
type SheetRowEntry record {|
    string sku;
    string productName;
    decimal quantityOnHand;
    decimal reorderThreshold;
|};
