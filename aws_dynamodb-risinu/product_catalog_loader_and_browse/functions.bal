import ballerina/lang.array;
import ballerina/lang.runtime;
import ballerina/log;
import ballerinax/aws.dynamodb;

const string SKU_ATTR = "Sku";
const string NAME_ATTR = "Name";
const string CATEGORY_ATTR = "Category";
const string PRICE_ATTR = "Price";

// DynamoDB's BatchWriteItem and BatchGetItem operations cap requests at 25 items.
const int DYNAMODB_BATCH_LIMIT = 25;

// Maximum attempts to retry any items DynamoDB reports back as unprocessed.
const int MAX_UNPROCESSED_RETRIES = 5;

// Finds the category index's description among a table's global secondary indexes, if it
// currently has one by that name.
function findCategoryIndex(dynamodb:TableDescription description) returns dynamodb:GlobalSecondaryIndexDescription? {
    dynamodb:GlobalSecondaryIndexDescription[]? indexes = description?.GlobalSecondaryIndexes;
    if indexes is () {
        return ();
    }
    foreach dynamodb:GlobalSecondaryIndexDescription index in indexes {
        if index?.IndexName == catalogCategoryIndexName {
            return index;
        }
    }
    return ();
}

// True once the index has finished building and is serving queries. Compared as text rather
// than against a specific enum member, since DynamoDB reports index status separately from
// table status and only ever as one of "CREATING", "UPDATING", "DELETING", or "ACTIVE".
function isIndexActive(dynamodb:GlobalSecondaryIndexDescription index) returns boolean {
    return index?.IndexStatus.toString() == "ACTIVE";
}

// Makes sure the category index exists and is ready to serve queries before the service starts
// accepting traffic, creating it on the already-existing table if it is missing. The table
// itself is provisioned externally and is never created here — only the index that category
// browsing and the category summary depend on.
//
// This is what keeps both of those reads scoped to the category they're asked about: without
// the index, the only way to group products by category is to walk the entire table.
function ensureCategoryIndexReady() returns error? {
    dynamodb:TableDescription|dynamodb:Error description = dynamoDbClient->describeTable(catalogTableName);
    if description is dynamodb:Error {
        log:printError("Catalog table could not be described; refusing to start",
                description, tableName = catalogTableName);
        return error("Catalog table is not accessible; the service will not start");
    }

    dynamodb:GlobalSecondaryIndexDescription? existingIndex = findCategoryIndex(description);
    if existingIndex is () {
        log:printInfo("Category index not found; creating it",
                tableName = catalogTableName, indexName = catalogCategoryIndexName);
        check createCategoryIndex(description);
    } else if isIndexActive(existingIndex) {
        log:printInfo("Category index is ready", tableName = catalogTableName,
                indexName = catalogCategoryIndexName);
        return ();
    }

    check waitForCategoryIndexActive();
}

// Issues the UpdateTable call that adds the category index to the table. Category and Price
// are not part of the table's own key, so they are declared as attributes here; Name is
// projected into the index so a category listing can be served entirely from it.
function createCategoryIndex(dynamodb:TableDescription tableDescription) returns error? {
    dynamodb:AttributeDefinition[] keyAttributeDefinitions = [
        {AttributeName: CATEGORY_ATTR, AttributeType: dynamodb:S},
        {AttributeName: PRICE_ATTR, AttributeType: dynamodb:N}
    ];

    dynamodb:CreateGlobalSecondaryIndexAction createAction = {
        IndexName: catalogCategoryIndexName,
        KeySchema: [
            {AttributeName: CATEGORY_ATTR, KeyType: dynamodb:HASH},
            {AttributeName: PRICE_ATTR, KeyType: dynamodb:RANGE}
        ],
        Projection: {ProjectionType: "INCLUDE", NonKeyAttributes: [NAME_ATTR]}
    };

    // A provisioned-throughput table needs the new index's own throughput specified; an
    // on-demand table (the common case) does not use this field at all.
    dynamodb:BillingMode? billingMode = tableDescription?.BillingModeSummary?.BillingMode;
    if billingMode == dynamodb:PROVISIONED {
        createAction.ProvisionedThroughput = {
            ReadCapacityUnits: INDEX_READ_CAPACITY_UNITS,
            WriteCapacityUnits: INDEX_WRITE_CAPACITY_UNITS
        };
    }

    dynamodb:TableDescription|dynamodb:Error updateResult = dynamoDbClient->updateTable({
        TableName: catalogTableName,
        AttributeDefinitions: keyAttributeDefinitions,
        GlobalSecondaryIndexUpdates: [{Create: createAction}]
    });
    if updateResult is dynamodb:Error {
        log:printError("Failed to create the category index; refusing to start",
                updateResult, tableName = catalogTableName, indexName = catalogCategoryIndexName);
        return error("Category index could not be created; the service will not start");
    }
}

// Polls the table description until the category index reports ACTIVE, so the service never
// starts serving category reads against an index that isn't actually usable yet.
function waitForCategoryIndexActive() returns error? {
    decimal waited = 0d;
    while waited < INDEX_READY_MAX_WAIT_SECONDS {
        dynamodb:TableDescription|dynamodb:Error description = dynamoDbClient->describeTable(catalogTableName);
        if description is dynamodb:Error {
            log:printError("Catalog table could not be described while waiting for the category index",
                    description, tableName = catalogTableName);
            return error("Catalog table is not accessible; the service will not start");
        }

        dynamodb:GlobalSecondaryIndexDescription? index = findCategoryIndex(description);
        if index is dynamodb:GlobalSecondaryIndexDescription && isIndexActive(index) {
            log:printInfo("Category index is ready", tableName = catalogTableName,
                    indexName = catalogCategoryIndexName);
            return ();
        }

        runtime:sleep(INDEX_READY_POLL_INTERVAL_SECONDS);
        waited += INDEX_READY_POLL_INTERVAL_SECONDS;
    }

    log:printError("Category index did not become ready in time; refusing to start",
            tableName = catalogTableName, indexName = catalogCategoryIndexName);
    return error("Category index is not ready; the service will not start");
}

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

// Looks up a single product by SKU. Returns () when there is no product under that SKU, which
// the caller turns into a 404 rather than treating as an error.
function getProduct(string sku) returns Product?|error {
    dynamodb:ItemGetOutput result = check dynamoDbClient->getItem({
        TableName: catalogTableName,
        Key: {[SKU_ATTR]: {S: sku}}
    });

    map<dynamodb:AttributeValue>? item = result?.Item;
    if item is () {
        return ();
    }
    return check fromItem(item);
}

// Encodes a page position into an opaque cursor. Base64url without padding, so the value the
// caller hands back in a query parameter is byte-for-byte the value we issued.
function encodeCursor(CursorState position) returns string {
    string encoded = position.toJsonString().toBytes().toBase64();
    encoded = re `\+`.replaceAll(encoded, "-");
    encoded = re `/`.replaceAll(encoded, "_");
    return re `=`.replaceAll(encoded, "");
}

// Reverses `encodeCursor`. Anything that isn't a cursor we issued comes back as an error so the
// caller gets a 400 rather than an arbitrary starting point in the catalog.
function decodeCursor(string cursor) returns CursorState|error {
    string encoded = re `-`.replaceAll(cursor, "+");
    encoded = re `_`.replaceAll(encoded, "/");
    // Restore the padding stripped by `encodeCursor`. A remainder of 1 is not valid base64 and
    // is left alone for the decoder to reject.
    int remainder = encoded.length() % 4;
    if remainder == 2 {
        encoded = encoded + "==";
    } else if remainder == 3 {
        encoded = encoded + "=";
    }
    byte[] decoded = check array:fromBase64(encoded);
    json parsed = check (check string:fromBytes(decoded)).fromJsonString();
    return parsed.cloneWithType();
}

// Returns one page of the products in a category, cheapest first, optionally capped at a
// maximum price. The query runs against the category index, and reads one item beyond the page
// so a full page can be told apart from the end of the results — that extra item is what makes
// `hasMore` trustworthy instead of leaving the caller to guess whether it was cut off.
//
// A category with no products is not a special case: the query simply matches nothing and an
// empty page comes back.
function browseCategory(string category, decimal? maxPrice, int pageSize, CursorState? startAfter)
        returns CategoryProductPage|error {
    string keyCondition = "#category = :category";
    map<dynamodb:AttributeValue> attributeValues = {":category": {S: category}};
    if maxPrice is decimal {
        // Price is the index sort key, so the cap narrows the key range that is read rather than
        // filtering items out after the fact.
        keyCondition = keyCondition + " AND #price <= :maxPrice";
        attributeValues[":maxPrice"] = {N: maxPrice.toString()};
    }

    dynamodb:QueryInput queryInput = {
        TableName: catalogTableName,
        IndexName: catalogCategoryIndexName,
        KeyConditionExpression: keyCondition,
        // Name and Price are DynamoDB reserved words, so attributes are referenced by placeholder.
        ExpressionAttributeNames: {
            "#category": CATEGORY_ATTR,
            "#sku": SKU_ATTR,
            "#name": NAME_ATTR,
            "#price": PRICE_ATTR
        },
        ExpressionAttributeValues: attributeValues,
        // Only the three fields the listing returns are read back off the index.
        ProjectionExpression: "#sku, #name, #price",
        Limit: pageSize + 1
    };

    if startAfter is CursorState {
        queryInput.ExclusiveStartKey = {
            [CATEGORY_ATTR]: {S: startAfter.category},
            [PRICE_ATTR]: {N: startAfter.price},
            [SKU_ATTR]: {S: startAfter.sku}
        };
    }

    stream<dynamodb:QueryOutput, dynamodb:Error?> matches = check dynamoDbClient->query(queryInput);

    ProductSummary[] products = [];
    CursorState? lastPosition = ();
    boolean hasMore = false;

    while true {
        record {|dynamodb:QueryOutput value;|}|dynamodb:Error? next = matches.next();
        if next is () {
            break;
        }
        if next is dynamodb:Error {
            return next;
        }

        map<dynamodb:AttributeValue>? item = next.value?.Item;
        if item is () {
            continue;
        }
        if products.length() == pageSize {
            // A further match exists beyond this page, so the caller is handed a cursor.
            hasMore = true;
            break;
        }

        dynamodb:AttributeValue? skuAttribute = item[SKU_ATTR];
        dynamodb:AttributeValue? nameAttribute = item[NAME_ATTR];
        dynamodb:AttributeValue? priceAttribute = item[PRICE_ATTR];
        if skuAttribute is () || nameAttribute is () || priceAttribute is () {
            return error("Stored product item is missing required attributes");
        }
        string? sku = skuAttribute?.S;
        string? name = nameAttribute?.S;
        string? priceText = priceAttribute?.N;
        if sku is () || name is () || priceText is () {
            return error("Stored product item has malformed attributes");
        }

        products.push({sku, name, price: check decimal:fromString(priceText)});
        // The index key of the last item returned is precisely where the next page resumes.
        lastPosition = {category, price: priceText, sku};
    }

    string? nextCursor = ();
    if hasMore && lastPosition is CursorState {
        nextCursor = encodeCursor(lastPosition);
    }
    return {category, products, hasMore, nextCursor};
}

// Summarises which categories currently hold products and roughly how many each holds.
//
// The tally is taken by streaming the category index and projecting nothing but the category
// attribute, so only the running counts are ever held in memory — no product is materialised,
// whatever the size of the catalog. Counts are approximate by nature: the index is eventually
// consistent, and a catalog being written to will have moved on by the time the walk finishes.
function summarizeCategories() returns CategorySummaryResponse|error {
    dynamodb:ScanInput scanInput = {
        TableName: catalogTableName,
        IndexName: catalogCategoryIndexName,
        ProjectionExpression: "#category",
        ExpressionAttributeNames: {"#category": CATEGORY_ATTR}
    };

    map<int> countsByCategory = {};
    stream<dynamodb:ScanOutput, dynamodb:Error?> entries = check dynamoDbClient->scan(scanInput);
    check from dynamodb:ScanOutput entry in entries
        do {
            map<dynamodb:AttributeValue>? item = entry?.Item;
            if item is map<dynamodb:AttributeValue> {
                dynamodb:AttributeValue? categoryAttribute = item[CATEGORY_ATTR];
                string? category = categoryAttribute is () ? () : categoryAttribute?.S;
                if category is string {
                    countsByCategory[category] = (countsByCategory[category] ?: 0) + 1;
                }
            }
        };

    CategoryCount[] categories = from var [category, count] in countsByCategory.entries()
        order by category ascending
        select {category, approximateProductCount: count};
    return {categories};
}
