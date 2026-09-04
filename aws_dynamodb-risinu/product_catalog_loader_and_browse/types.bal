// A validated product to be loaded into the catalog.
public type Product record {|
    string sku;
    string name;
    string category;
    decimal price;
|};

// A product exactly as received on the wire, before validation. sku and price are left
// loosely typed so a missing sku or a non-numeric price can be reported as a named 400
// instead of a generic data-binding failure.
public type RawProduct record {|
    json sku?;
    string name = "";
    string category = "";
    json price?;
|};

// Request body for the bulk load call: a batch of products to write in one go.
public type ProductBatchLoadRequest record {|
    RawProduct[] products;
|};

// Response for a fully accepted bulk load.
public type ProductBatchLoadAccepted record {|
    int loadedCount;
|};

// Names the specific product in the request that failed validation, so the caller can
// tell exactly which entry was rejected. Nothing from the request is written in this case.
public type InvalidProductDetail record {|
    string? sku;
    string reason;
|};

// Response body for a rejected bulk load request.
public type InvalidProductBatch record {|
    string message;
    InvalidProductDetail invalidProduct;
|};

// Response for a single product lookup by SKU.
public type ProductLookupResult record {|
    string sku;
    Product? product;
    boolean found;
|};

// Response body for the multi-SKU lookup call.
public type ProductBatchLookupResponse record {|
    ProductLookupResult[] results;
|};

// A product as returned by a category listing. These responses get large, so only the three
// fields a browsing caller needs are sent back rather than the whole stored record.
public type ProductSummary record {|
    string sku;
    string name;
    decimal price;
|};

// One page of a category listing. `nextCursor` is present exactly when more matching products
// remain, so a caller can always tell a complete result from a partial one and work through the
// rest — it is never silently truncated.
public type CategoryProductPage record {|
    string category;
    ProductSummary[] products;
    boolean hasMore;
    string? nextCursor;
|};

// Where a page stopped, carried inside the opaque cursor. This is the index key of the last
// product returned, so the next page resumes exactly after it. `price` stays a string to keep
// DynamoDB's own numeric representation intact across the round trip, and the category is
// carried along so a cursor cannot be replayed against a different category.
type CursorState record {|
    string category;
    string price;
    string sku;
|};

// Approximate number of products currently held in one category.
public type CategoryCount record {|
    string category;
    int approximateProductCount;
|};

// Response body for the catalog summary: every category currently holding at least one product.
public type CategorySummaryResponse record {|
    CategoryCount[] categories;
|};
