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
