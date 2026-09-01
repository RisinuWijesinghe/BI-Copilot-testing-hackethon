import ballerina/http;
import ballerina/test;
import ballerinax/googleapis.sheets;

final http:Client testStockClient = check new ("http://localhost:8080/stock");

@test:Mock {functionName: "initializeSheetsClient"}
function getMockSheetsClient() returns sheets:Client|error {
    return test:mock(sheets:Client);
}

@test:Config {}
function testGetStockRejectsMalformedSku() returns error? {
    http:Response response = check testStockClient->get("/bad%20sku!");
    test:assertEquals(response.statusCode, 400, msg = "expected a bad request for a malformed sku");
}

@test:Config {}
function testGetStockReturnsNotFoundForUnknownSku() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("getRange").thenReturn(<sheets:Range>{
        a1Notation: "A2:D",
        values: [
            ["SKU-1", "Widget", 10d, 5d]
        ]
    });

    http:Response response = check testStockClient->get("/SKU-999");
    test:assertEquals(response.statusCode, 404, msg = "expected a not-found for an unknown sku");
}

@test:Config {}
function testGetStockReturnsLevelForKnownSku() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("getRange").thenReturn(<sheets:Range>{
        a1Notation: "A2:D",
        values: [
            ["SKU-1", "Widget", 10d, 5d]
        ]
    });

    http:Response response = check testStockClient->get("/SKU-1");
    test:assertEquals(response.statusCode, 200, msg = "expected a successful stock level response");

    StockLevel stockLevel = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(stockLevel.sku, "SKU-1", msg = "unexpected sku in stock level");
    test:assertEquals(stockLevel.quantityOnHand, 10d, msg = "unexpected quantity on hand");
    test:assertFalse(stockLevel.lowStock, msg = "did not expect low stock to be flagged");
}

// -----------------------------------------------------------------------------------------
// Single movement rules
// -----------------------------------------------------------------------------------------

@test:Config {}
function testPostMovementRejectsMalformedSku() returns error? {
    http:Response response = check testStockClient->post("/bad%20sku!/movements", {quantityChange: 5});
    test:assertEquals(response.statusCode, 400, msg = "expected a bad request for a malformed sku");
}

@test:Config {}
function testPostMovementRejectsZeroQuantity() returns error? {
    http:Response response = check testStockClient->post("/SKU-1/movements", {quantityChange: 0});
    test:assertEquals(response.statusCode, 400, msg = "expected a bad request for a zero movement");

    json responseBody = check response.getJsonPayload();
    map<json> responseBodyMap = <map<json>>responseBody;
    test:assertEquals(responseBodyMap["message"], "quantityChange must not be zero",
            msg = "unexpected rejection message for a zero movement");
}

@test:Config {}
function testPostMovementReturnsNotFoundForUnknownSku() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("getRange").thenReturn(<sheets:Range>{
        a1Notation: "A2:D",
        values: [
            ["SKU-1", "Widget", 10d, 5d]
        ]
    });

    http:Response response = check testStockClient->post("/SKU-999/movements", {quantityChange: 5});
    test:assertEquals(response.statusCode, 404, msg = "expected a not-found for an unknown sku");
}

@test:Config {}
function testPostMovementAppliesDeliveryAndReportsLowStockFlag() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("getRange").thenReturn(<sheets:Range>{
        a1Notation: "A2:D",
        values: [
            ["SKU-1", "Widget", 2d, 5d]
        ]
    });
    sheetsClientMock.when("setCell").thenReturn(());

    http:Response response = check testStockClient->post("/SKU-1/movements", {quantityChange: 1});
    test:assertEquals(response.statusCode, 201, msg = "expected the movement to be applied");

    MovementResult result = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(result.previousQuantity, 2d, msg = "unexpected previous quantity");
    test:assertEquals(result.newQuantity, 3d, msg = "unexpected new quantity");
    test:assertTrue(result.lowStock, msg = "expected low stock to still be flagged (3 <= threshold 5)");
}

@test:Config {}
function testPostMovementAppliesWithdrawalAboveThreshold() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("getRange").thenReturn(<sheets:Range>{
        a1Notation: "A2:D",
        values: [
            ["SKU-1", "Widget", 20d, 5d]
        ]
    });
    sheetsClientMock.when("setCell").thenReturn(());

    http:Response response = check testStockClient->post("/SKU-1/movements", {quantityChange: -5});
    test:assertEquals(response.statusCode, 201, msg = "expected the movement to be applied");

    MovementResult result = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(result.previousQuantity, 20d, msg = "unexpected previous quantity");
    test:assertEquals(result.newQuantity, 15d, msg = "unexpected new quantity");
    test:assertFalse(result.lowStock, msg = "did not expect low stock to be flagged");
}

@test:Config {}
function testPostMovementRejectsMovementBelowZero() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("getRange").thenReturn(<sheets:Range>{
        a1Notation: "A2:D",
        values: [
            ["SKU-1", "Widget", 4d, 5d]
        ]
    });

    http:Response response = check testStockClient->post("/SKU-1/movements", {quantityChange: -10});
    test:assertEquals(response.statusCode, 409, msg = "expected a conflict when the movement would go below zero");

    json responseBody = check response.getJsonPayload();
    map<json> responseBodyMap = <map<json>>responseBody;
    test:assertEquals(responseBodyMap["message"], "movement rejected: insufficient stock available",
            msg = "unexpected rejection message");
    test:assertEquals(responseBodyMap["availableQuantity"], 4, msg = "expected the available quantity to be reported");
}

@test:Config {}
function testPostMovementReturnsGenericMessageWhenWriteFails() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("getRange").thenReturn(<sheets:Range>{
        a1Notation: "A2:D",
        values: [
            ["SKU-1", "Widget", 10d, 5d]
        ]
    });
    sheetsClientMock.when("setCell").thenReturn(error("internal error, credentials invalid"));

    http:Response response = check testStockClient->post("/SKU-1/movements", {quantityChange: 5});
    test:assertEquals(response.statusCode, 500, msg = "expected a server error when the sheet write fails");

    json responseBody = check response.getJsonPayload();
    map<json> responseBodyMap = <map<json>>responseBody;
    test:assertEquals(responseBodyMap["message"], "could not record the stock movement, please retry",
            msg = "the response must not leak upstream error details");
}

// -----------------------------------------------------------------------------------------
// Bulk movements
// -----------------------------------------------------------------------------------------

@test:Config {}
function testPostBulkMovementRejectsEmptyRequest() returns error? {
    http:Response response = check testStockClient->post("/movements", <json[]>[]);
    test:assertEquals(response.statusCode, 400, msg = "expected a bad request for an empty bulk request");
}

@test:Config {}
function testPostBulkMovementRejectsDuplicateSkus() returns error? {
    json requestBody = [
        {sku: "SKU-1", quantityChange: 5},
        {sku: "sku-1", quantityChange: -2}
    ];

    http:Response response = check testStockClient->post("/movements", requestBody);
    test:assertEquals(response.statusCode, 400, msg = "expected a bad request when the same sku is repeated");

    json responseBody = check response.getJsonPayload();
    map<json> responseBodyMap = <map<json>>responseBody;
    string message = <string>responseBodyMap["message"];
    test:assertTrue(message.includes("duplicate sku"), msg = "expected the rejection to mention duplicate skus");
}

@test:Config {}
function testPostBulkMovementReportsPartialSuccessShape() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("getRange").thenReturn(<sheets:Range>{
        a1Notation: "A2:D",
        values: [
            ["SKU-1", "Widget", 10d, 5d],
            ["SKU-2", "Gadget", 3d, 5d]
        ]
    });
    sheetsClientMock.when("setCell").thenReturn(());

    json requestBody = [
        {sku: "SKU-1", quantityChange: 5},
        {sku: "SKU-2", quantityChange: -100},
        {sku: "SKU-999", quantityChange: 1}
    ];

    http:Response response = check testStockClient->post("/movements", requestBody);
    test:assertEquals(response.statusCode, 201, msg = "expected the bulk endpoint to respond even with partial failures");

    BulkMovementResult result = check (check response.getJsonPayload()).cloneWithType();
    test:assertFalse(result.allApplied, msg = "expected allApplied to be false when any line fails");
    test:assertEquals(result.results.length(), 3, msg = "expected one outcome per requested line");

    MovementOutcome firstOutcome = result.results[0];
    test:assertEquals(firstOutcome.sku, "SKU-1", msg = "unexpected sku for first outcome");
    test:assertEquals(firstOutcome.status, "APPLIED", msg = "expected the first line to be applied");
    test:assertEquals(firstOutcome.newQuantity, 15d, msg = "unexpected new quantity for first outcome");

    MovementOutcome secondOutcome = result.results[1];
    test:assertEquals(secondOutcome.sku, "SKU-2", msg = "unexpected sku for second outcome");
    test:assertEquals(secondOutcome.status, "INSUFFICIENT_STOCK", msg = "expected the second line to be rejected for insufficient stock");

    MovementOutcome thirdOutcome = result.results[2];
    test:assertEquals(thirdOutcome.sku, "SKU-999", msg = "unexpected sku for third outcome");
    test:assertEquals(thirdOutcome.status, "NOT_FOUND", msg = "expected the third line to be not-found");
}

@test:Config {}
function testPostBulkMovementAllAppliedWhenEverythingSucceeds() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("getRange").thenReturn(<sheets:Range>{
        a1Notation: "A2:D",
        values: [
            ["SKU-1", "Widget", 10d, 5d],
            ["SKU-2", "Gadget", 20d, 5d]
        ]
    });
    sheetsClientMock.when("setCell").thenReturn(());

    json requestBody = [
        {sku: "SKU-1", quantityChange: 5},
        {sku: "SKU-2", quantityChange: -1}
    ];

    http:Response response = check testStockClient->post("/movements", requestBody);
    test:assertEquals(response.statusCode, 201, msg = "expected the bulk endpoint to succeed");

    BulkMovementResult result = check (check response.getJsonPayload()).cloneWithType();
    test:assertTrue(result.allApplied, msg = "expected allApplied to be true when every line succeeds");
    foreach MovementOutcome outcome in result.results {
        test:assertEquals(outcome.status, "APPLIED", msg = "expected every line to be applied");
    }
}

// -----------------------------------------------------------------------------------------
// Retire
// -----------------------------------------------------------------------------------------

@test:Config {}
function testDeleteSkuRejectsMalformedSku() returns error? {
    http:Response response = check testStockClient->delete("/bad%20sku!");
    test:assertEquals(response.statusCode, 400, msg = "expected a bad request for a malformed sku");
}

@test:Config {}
function testDeleteSkuReturnsNotFoundForUnknownSku() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("getRange").thenReturn(<sheets:Range>{
        a1Notation: "A2:D",
        values: [
            ["SKU-1", "Widget", 0d, 5d]
        ]
    });

    http:Response response = check testStockClient->delete("/SKU-999");
    test:assertEquals(response.statusCode, 404, msg = "expected a not-found for an unknown sku");
}

@test:Config {}
function testDeleteSkuRejectsWhenStockRemains() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("getRange").thenReturn(<sheets:Range>{
        a1Notation: "A2:D",
        values: [
            ["SKU-1", "Widget", 4d, 5d]
        ]
    });

    http:Response response = check testStockClient->delete("/SKU-1");
    test:assertEquals(response.statusCode, 409, msg = "expected a conflict when stock remains on hand");

    json responseBody = check response.getJsonPayload();
    map<json> responseBodyMap = <map<json>>responseBody;
    test:assertEquals(responseBodyMap["message"], "sku cannot be retired while stock remains on hand",
            msg = "unexpected rejection message");
    test:assertEquals(responseBodyMap["quantityOnHand"], 4, msg = "expected the remaining quantity to be reported");
}

@test:Config {}
function testDeleteSkuSucceedsWhenNoStockRemains() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("getRange").thenReturn(<sheets:Range>{
        a1Notation: "A2:D",
        values: [
            ["SKU-1", "Widget", 0d, 5d]
        ]
    });
    sheetsClientMock.when("deleteRowsBySheetName").thenReturn(());

    http:Response response = check testStockClient->delete("/SKU-1");
    test:assertEquals(response.statusCode, 200, msg = "expected the retirement to succeed");

    RetireResult result = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(result.sku, "SKU-1", msg = "unexpected sku in retirement confirmation");
    test:assertEquals(result.message, "sku retired", msg = "unexpected retirement confirmation message");
}

@test:Config {}
function testDeleteSkuReturnsGenericMessageWhenDeleteFails() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("getRange").thenReturn(<sheets:Range>{
        a1Notation: "A2:D",
        values: [
            ["SKU-1", "Widget", 0d, 5d]
        ]
    });
    sheetsClientMock.when("deleteRowsBySheetName").thenReturn(error("internal error, credentials invalid"));

    http:Response response = check testStockClient->delete("/SKU-1");
    test:assertEquals(response.statusCode, 500, msg = "expected a server error when the row deletion fails");

    json responseBody = check response.getJsonPayload();
    map<json> responseBodyMap = <map<json>>responseBody;
    test:assertEquals(responseBodyMap["message"], "could not retire the sku, please retry",
            msg = "the response must not leak upstream error details");
}

