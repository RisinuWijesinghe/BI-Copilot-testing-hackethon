import ballerina/http;
import ballerina/test;
import ballerinax/aws.dynamodb;

// Startup's category-index readiness check performs real AWS calls (describeTable, and
// possibly updateTable); it is replaced with a no-op for the test run so module initialization
// does not require live AWS access. The check itself is exercised separately from the request
// handling behaviour covered here.
@test:Mock {
    functionName: "ensureCategoryIndexReady"
}
function mockEnsureCategoryIndexReady() returns error? {
    return ();
}

final http:Client catalogClient = check new (string `http://localhost:${servicePort}/catalog`);

// ----------------------------------------------------------------------------------
// Loader: all-or-nothing reporting.
// ----------------------------------------------------------------------------------

@test:Config {}
function testValidBatchIsFullyAccepted() returns error? {
    test:prepare(dynamoDbClient).when("writeBatchItems").thenReturn(<dynamodb:BatchItemInsertOutput>{});

    json payload = {
        products: [
            {sku: "SKU-1", name: "Widget", category: "Tools", price: 9.99},
            {sku: "SKU-2", name: "Gadget", category: "Tools", price: 19.99}
        ]
    };
    ProductBatchLoadAccepted response = check catalogClient->post("/products", payload);

    test:assertEquals(response.loadedCount, 2, msg = "both products in the batch should be reported as loaded");
}

@test:Config {}
function testBatchWithMissingSkuIsRejectedAndNothingWritten() returns error? {
    json payload = {
        products: [
            {sku: "SKU-1", name: "Widget", category: "Tools", price: 9.99},
            {name: "Unnamed", category: "Tools", price: 4.99}
        ]
    };
    http:Response response = check catalogClient->post("/products", payload);
    json responseBody = check response.getJsonPayload();

    test:assertEquals(response.statusCode, 400, msg = "a product missing a sku should be a 400");
    string responseText = responseBody.toJsonString();
    test:assertTrue(responseText.includes("sku"), msg = "the 400 should name the sku problem");
}

@test:Config {}
function testBatchWithNonNumericPriceIsRejectedAndNothingWritten() returns error? {
    json payload = {
        products: [
            {sku: "SKU-1", name: "Widget", category: "Tools", price: "not-a-number"}
        ]
    };
    http:Response response = check catalogClient->post("/products", payload);
    json responseBody = check response.getJsonPayload();

    test:assertEquals(response.statusCode, 400, msg = "a non-numeric price should be a 400");
    string responseText = responseBody.toJsonString();
    test:assertTrue(responseText.includes("SKU-1"),
            msg = "the 400 should name the offending product by sku");
    test:assertTrue(responseText.includes("price"), msg = "the 400 should name the price problem");
}

@test:Config {}
function testAwsFailureDuringLoadIsGeneric502WithNothingConfirmed() returns error? {
    dynamodb:Error awsFailure = error dynamodb:Error(
            "AccessDeniedException: User arn:aws:iam::123456789012:user/svc is not authorized " +
            "to perform dynamodb:BatchWriteItem on resource GameCatalog",
            httpStatusCode = 403);
    test:prepare(dynamoDbClient).when("writeBatchItems").thenReturn(awsFailure);

    json payload = {
        products: [
            {sku: "SKU-9", name: "Thingamajig", category: "Tools", price: 5.5}
        ]
    };
    http:Response response = check catalogClient->post("/products", payload);
    json responseBody = check response.getJsonPayload();
    string responseText = responseBody.toJsonString();

    test:assertEquals(response.statusCode, 502, msg = "an AWS failure during load should surface as a 502");
    test:assertTrue(!responseText.includes("AccessDeniedException"),
            msg = "the raw AWS error must not appear in the response");
    test:assertTrue(!responseText.includes(catalogTableName),
            msg = "the table name must not appear in the response");
    test:assertTrue(!responseText.includes("123456789012"),
            msg = "account details must not appear in the response");
}

@test:Config {}
function testUnprocessedItemsAfterRetriesIsGeneric502() returns error? {
    // DynamoDB reports the item back as unprocessed on every attempt; the write is never
    // confirmed, so success must never be reported for it.
    map<dynamodb:AttributeValue> unwrittenItem = {
        "Sku": {S: "SKU-STUCK"},
        "Name": {S: "Stuck Widget"},
        "Category": {S: "Tools"},
        "Price": {N: "1"}
    };
    dynamodb:BatchItemInsertOutput stillUnprocessed = {
        UnprocessedItems: {
            [catalogTableName]: [{PutRequest: {Item: unwrittenItem}}]
        }
    };
    test:prepare(dynamoDbClient).when("writeBatchItems").thenReturn(stillUnprocessed);

    json payload = {
        products: [
            {sku: "SKU-STUCK", name: "Stuck Widget", category: "Tools", price: 1}
        ]
    };
    http:Response response = check catalogClient->post("/products", payload);

    test:assertEquals(response.statusCode, 502,
            msg = "items left unprocessed after retries must not be reported as loaded");
}

// ----------------------------------------------------------------------------------
// Category browsing: touches only the requested category.
// ----------------------------------------------------------------------------------

@test:Config {}
function testCategoryPageReturnsOnlySkuNameAndPriceCheapestFirst() returns error? {
    test:prepare(dynamoDbClient).when("query").thenReturn(mockQueryStream([
        {sku: "SKU-A", name: "Hammer", price: 12.5},
        {sku: "SKU-B", name: "Wrench", price: 15.0}
    ]));

    CategoryProductPage response = check catalogClient->get("/categories/Tools/products?limit=50");

    test:assertEquals(response.category, "Tools", msg = "category should echo the path parameter");
    test:assertEquals(response.products.length(), 2, msg = "both matching products should be returned");
    test:assertEquals(response.products[0], {sku: "SKU-A", name: "Hammer", price: 12.5d},
            msg = "product fields should be limited to sku, name and price");
    test:assertFalse(response.hasMore, msg = "a full result under the page size has no further page");
    test:assertEquals(response.nextCursor, (), msg = "no cursor is issued when there is no further page");
}

@test:Config {}
function testCategoryPageSignalsMoreResultsWithACursor() returns error? {
    // One more item than the requested page size comes back; the extra item is what makes
    // hasMore trustworthy rather than a guess.
    test:prepare(dynamoDbClient).when("query").thenReturn(mockQueryStream([
        {sku: "SKU-A", name: "Hammer", price: 10.0},
        {sku: "SKU-B", name: "Wrench", price: 12.0},
        {sku: "SKU-C", name: "Pliers", price: 14.0}
    ]));

    CategoryProductPage response = check catalogClient->get("/categories/Tools/products?limit=2");

    test:assertEquals(response.products.length(), 2, msg = "only the requested page size should be returned");
    test:assertTrue(response.hasMore, msg = "an extra matching item beyond the page means more remain");
    string? nextCursor = response.nextCursor;
    test:assertTrue(nextCursor is string, msg = "a cursor should be issued when more results remain");
}

@test:Config {}
function testUnknownCategoryIsAnEmptyPageNotAnError() returns error? {
    test:prepare(dynamoDbClient).when("query").thenReturn(mockEmptyQueryStream());

    CategoryProductPage response = check catalogClient->get("/categories/Nonexistent/products");

    test:assertEquals(response.category, "Nonexistent", msg = "category should echo the path parameter");
    test:assertEquals(response.products, [], msg = "an unknown category should return an empty product list");
    test:assertFalse(response.hasMore, msg = "an empty result has no further page");
}

@test:Config {}
function testInvalidLimitIsA400() returns error? {
    http:Response tooLow = check catalogClient->get("/categories/Tools/products?limit=0");
    test:assertEquals(tooLow.statusCode, 400, msg = "a limit below 1 should be a 400");

    http:Response tooHigh = check catalogClient->get(string `/categories/Tools/products?limit=${MAX_PAGE_SIZE + 1}`);
    test:assertEquals(tooHigh.statusCode, 400, msg = "a limit above the maximum should be a 400");
}

@test:Config {}
function testInvalidCursorIsA400() returns error? {
    http:Response response = check catalogClient->get("/categories/Tools/products?cursor=not-a-real-cursor!!");
    test:assertEquals(response.statusCode, 400, msg = "a cursor that doesn't decode should be a 400");
}

@test:Config {}
function testAwsFailureOnCategoryReadIsGeneric502() returns error? {
    dynamodb:Error awsFailure = error dynamodb:Error(
            "ProvisionedThroughputExceededException on table GameCatalog in account 123456789012",
            httpStatusCode = 400);
    test:prepare(dynamoDbClient).when("query").thenReturn(awsFailure);

    http:Response response = check catalogClient->get("/categories/Tools/products");
    json responseBody = check response.getJsonPayload();
    string responseText = responseBody.toJsonString();

    test:assertEquals(response.statusCode, 502, msg = "an AWS failure should surface as a 502");
    test:assertTrue(!responseText.includes(catalogTableName),
            msg = "the table name must not appear in the response");
    test:assertTrue(!responseText.includes("123456789012"),
            msg = "account details must not appear in the response");
}

// ----------------------------------------------------------------------------------
// Category summary.
// ----------------------------------------------------------------------------------

@test:Config {}
function testCategorySummaryReturnsApproximateCounts() returns error? {
    test:prepare(dynamoDbClient).when("scan").thenReturn(mockScanStreamOfCategories([
        "Tools", "Tools", "Kitchen", "Tools", "Kitchen"
    ]));

    CategorySummaryResponse response = check catalogClient->get("/categories");

    test:assertEquals(response.categories.length(), 2, msg = "two distinct categories should be reported");
    CategoryCount[] categories = response.categories;
    test:assertEquals(categories[0], {category: "Kitchen", approximateProductCount: 2},
            msg = "Kitchen's approximate count should be tallied correctly");
    test:assertEquals(categories[1], {category: "Tools", approximateProductCount: 3},
            msg = "Tools' approximate count should be tallied correctly");
}

// ----------------------------------------------------------------------------------
// Single-SKU lookup: 404 when the product isn't there.
// ----------------------------------------------------------------------------------

@test:Config {}
function testProductLookupNotFoundIs404() returns error? {
    test:prepare(dynamoDbClient).when("getItem").thenReturn(<dynamodb:ItemGetOutput>{});

    http:Response response = check catalogClient->get("/products/UNKNOWN-SKU");

    test:assertEquals(response.statusCode, 404, msg = "an unknown sku should be a 404");
}

@test:Config {}
function testProductLookupReturnsStoredProduct() returns error? {
    test:prepare(dynamoDbClient).when("getItem").thenReturn(<dynamodb:ItemGetOutput>{
        Item: {
            "Sku": {S: "SKU-1"},
            "Name": {S: "Widget"},
            "Category": {S: "Tools"},
            "Price": {N: "9.99"}
        }
    });

    Product response = check catalogClient->get("/products/SKU-1");

    test:assertEquals(response, {sku: "SKU-1", name: "Widget", category: "Tools", price: 9.99d},
            msg = "the stored product should be returned in full");
}

@test:Config {}
function testAwsFailureOnProductLookupIsGeneric502() returns error? {
    dynamodb:Error awsFailure = error dynamodb:Error(
            "AccessDeniedException on table GameCatalog in account 123456789012",
            httpStatusCode = 403);
    test:prepare(dynamoDbClient).when("getItem").thenReturn(awsFailure);

    http:Response response = check catalogClient->get("/products/SKU-1");
    json responseBody = check response.getJsonPayload();
    string responseText = responseBody.toJsonString();

    test:assertEquals(response.statusCode, 502, msg = "an AWS failure should surface as a 502");
    test:assertTrue(!responseText.includes(catalogTableName),
            msg = "the table name must not appear in the response");
    test:assertTrue(!responseText.includes("123456789012"),
            msg = "account details must not appear in the response");
}

// ----------------------------------------------------------------------------------
// Test helpers
// ----------------------------------------------------------------------------------

type MockCategoryProduct record {|
    string sku;
    string name;
    decimal price;
|};

function mockQueryStream(MockCategoryProduct[] products) returns stream<dynamodb:QueryOutput, dynamodb:Error?> {
    dynamodb:QueryOutput[] results = from MockCategoryProduct product in products
        select {
            Item: {
                "Sku": {S: product.sku},
                "Name": {S: product.name},
                "Price": {N: product.price.toString()}
            }
        };
    return results.toStream();
}

function mockEmptyQueryStream() returns stream<dynamodb:QueryOutput, dynamodb:Error?> {
    dynamodb:QueryOutput[] noResults = [];
    return noResults.toStream();
}

function mockScanStreamOfCategories(string[] categories) returns stream<dynamodb:ScanOutput, dynamodb:Error?> {
    dynamodb:ScanOutput[] results = from string category in categories
        select {
            Item: {
                "Category": {S: category}
            }
        };
    return results.toStream();
}
