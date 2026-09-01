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

# A single line item of a bulk movement request: a SKU and the quantity to move against it.
public type SkuMovement record {|
    string sku;
    decimal quantityChange;
|};

# The fixed set of outcomes a single line of a bulk movement request can settle into.
public type MovementOutcomeStatus "APPLIED"|"INVALID"|"NOT_FOUND"|"INSUFFICIENT_STOCK"|"FAILED"|"DUPLICATE_SKU";

# The outcome of a single line of a bulk movement request. `newQuantity`, `previousQuantity` and
# `lowStock` are only meaningful when `status` is `APPLIED`.
public type MovementOutcome record {|
    string sku;
    MovementOutcomeStatus status;
    string message;
    decimal previousQuantity?;
    decimal newQuantity?;
    decimal reorderThreshold?;
    boolean lowStock?;
|};

# Result of applying a batch of stock movements in one request. `allApplied` is `false` whenever
# at least one line did not succeed, making a partial outcome unmistakable at a glance.
public type BulkMovementResult record {|
    boolean allApplied;
    MovementOutcome[] results;
|};

# Confirmation returned after a SKU has been retired (its row removed from the sheet).
public type RetireResult record {|
    string sku;
    string message;
|};

# Represents a retirement that was refused because the SKU still has stock on hand.
public type StockRemainingDetail record {|
    string message;
    decimal quantityOnHand;
|};
