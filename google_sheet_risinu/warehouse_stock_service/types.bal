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

# A located stock row: the parsed entry plus its absolute row position in the sheet, needed to
# write an update back to the exact same row.
type LocatedStockRow record {|
    *SheetRowEntry;
    int rowPosition;
|};

# Incoming request to move stock for a SKU. A positive quantity is a delivery in, a negative
# quantity is goods going out.
public type StockMovement record {|
    decimal quantityChange;
|};

# Confirmation returned after a stock movement has been applied.
public type MovementResult record {|
    string sku;
    decimal previousQuantity;
    decimal newQuantity;
    decimal reorderThreshold;
    boolean lowStock;
|};

# Represents a movement that was refused because it would take stock below zero.
public type InsufficientStockDetail record {|
    string message;
    decimal availableQuantity;
|};
