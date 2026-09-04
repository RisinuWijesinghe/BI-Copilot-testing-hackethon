import ballerina/lang.runtime;
import ballerinax/aws.dynamodb;

const string SKU_ATTR = "Sku";
const string NAME_ATTR = "Name";
const string CATEGORY_ATTR = "Category";
const string PRICE_ATTR = "Price";

// DynamoDB's BatchWriteItem and BatchGetItem operations cap requests at 25 items.
const int DYNAMODB_BATCH_LIMIT = 25;

// Maximum attempts to retry any items DynamoDB reports back as unprocessed.
const int MAX_UNPROCESSED_RETRIES = 5;

// Validates a single raw product and converts it into a Product ready to write. Returns an
// InvalidProductDetail naming the offending product (by SKU, when it has one) if the SKU is
// missing or the price is not a number.
function validateProduct(RawProduct rawProduct) returns Product|InvalidProductDetail {
    json? skuJson = rawProduct?.sku;
    if skuJson is () || skuJson !is string || skuJson.trim().length() == 0 {
        return {sku: (), reason: "sku is required and must be a non-empty string"};
    }
    string sku = skuJson;

    json? priceJson = rawProduct?.price;
    if priceJson is () || (priceJson !is int && priceJson !is float && priceJson !is decimal) {
        return {sku, reason: "price is required and must be a number"};
    }
    decimal|error price = decimal:fromString(priceJson.toString());
    if price is error {
        return {sku, reason: "price is required and must be a number"};
    }

    return {sku, name: rawProduct.name, category: rawProduct.category, price};
}

// Converts a validated product into the DynamoDB item representation.
function toItem(Product product) returns map<dynamodb:AttributeValue> {
    return {
        [SKU_ATTR]: {S: product.sku},
        [NAME_ATTR]: {S: product.name},
        [CATEGORY_ATTR]: {S: product.category},
        [PRICE_ATTR]: {N: product.price.toString()}
    };
}

// Converts a DynamoDB item back into a Product.
function fromItem(map<dynamodb:AttributeValue> item) returns Product|error {
    dynamodb:AttributeValue? skuAttribute = item[SKU_ATTR];
    dynamodb:AttributeValue? nameAttribute = item[NAME_ATTR];
    dynamodb:AttributeValue? categoryAttribute = item[CATEGORY_ATTR];
    dynamodb:AttributeValue? priceAttribute = item[PRICE_ATTR];

    if skuAttribute is () || nameAttribute is () || categoryAttribute is () || priceAttribute is () {
        return error("Stored product item is missing required attributes");
    }

    string? sku = skuAttribute?.S;
    string? name = nameAttribute?.S;
    string? category = categoryAttribute?.S;
    string? priceString = priceAttribute?.N;
    if sku is () || name is () || category is () || priceString is () {
        return error("Stored product item has malformed attributes");
    }

    decimal price = check decimal:fromString(priceString);
    return {sku, name, category, price};
}

// Splits an array into fixed-size chunks, used to stay within DynamoDB's per-batch item limit.
function chunk(dynamodb:WriteRequest[] requests, int chunkSize) returns dynamodb:WriteRequest[][] {
    dynamodb:WriteRequest[][] chunks = [];
    int total = requests.length();
    int offset = 0;
    while offset < total {
        int end = offset + chunkSize;
        if end > total {
            end = total;
        }
        chunks.push(requests.slice(offset, end));
        offset = end;
    }
    return chunks;
}

// Writes one batch (at most DYNAMODB_BATCH_LIMIT items) of put-requests, retrying any items
// DynamoDB reports back as unprocessed. Returns an error if items remain unprocessed after
// all retries, so the caller never reports success while some products silently failed to land.
function writeBatchWithRetry(dynamodb:WriteRequest[] batch) returns error? {
    dynamodb:WriteRequest[] remaining = batch;
    int attempt = 0;
    while remaining.length() > 0 {
        if attempt >= MAX_UNPROCESSED_RETRIES {
            return error("DynamoDB left items unprocessed after repeated retries");
        }
        dynamodb:BatchItemInsertOutput|dynamodb:Error result = dynamoDbClient->writeBatchItems({
            RequestItems: {[catalogTableName]: remaining}
        });
        if result is dynamodb:Error {
            return result;
        }

        map<dynamodb:WriteRequest[]>? unprocessedItems = result?.UnprocessedItems;
        if unprocessedItems is () {
            return ();
        }
        dynamodb:WriteRequest[]? unprocessedForTable = unprocessedItems[catalogTableName];
        if unprocessedForTable is () || unprocessedForTable.length() == 0 {
            return ();
        }
        remaining = unprocessedForTable;
        attempt += 1;
        runtime:sleep(0.5 * <decimal>attempt);
    }
}

// Loads every product in the batch into DynamoDB. All products must already be validated by
// the caller. Writes are chunked to respect DynamoDB's per-batch item limit, and every chunk
// must be fully confirmed written — if any chunk fails, an error is returned and the caller
// must not report success for the whole batch.
function loadProducts(Product[] products) returns error? {
    dynamodb:WriteRequest[] writeRequests = from Product product in products
        select {PutRequest: {Item: toItem(product)}};

    dynamodb:WriteRequest[][] batches = chunk(writeRequests, DYNAMODB_BATCH_LIMIT);
    foreach dynamodb:WriteRequest[] batch in batches {
        check writeBatchWithRetry(batch);
    }
}

// Looks up a handful of SKUs in one round trip, reporting which of them were found.
function lookupProducts(string[] skus) returns ProductBatchLookupResponse|error {
    map<dynamodb:AttributeValue>[] keys = from string sku in skus
        select {[SKU_ATTR]: {S: sku}};

    dynamodb:BatchItemGetInput getInput = {
        RequestItems: {
            [catalogTableName]: {Keys: keys}
        }
    };

    map<Product> foundBySku = {};
    stream<dynamodb:BatchItem, dynamodb:Error?> items = check dynamoDbClient->getBatchItems(getInput);
    check from dynamodb:BatchItem batchItem in items
        do {
            map<dynamodb:AttributeValue> item = check batchItem?.Item.ensureType();
            Product product = check fromItem(item);
            foundBySku[product.sku] = product;
        };

    ProductLookupResult[] results = from string sku in skus
        select {
            sku,
            product: foundBySku[sku],
            found: foundBySku.hasKey(sku)
        };

    return {results};
}
