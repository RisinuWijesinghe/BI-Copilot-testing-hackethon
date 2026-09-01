import ballerina/http;
import ballerina/test;
import ballerinax/googleapis.sheets;

final http:Client testClaimsClient = check new ("http://localhost:8080/claims");

@test:Mock {functionName: "initializeSheetsClient"}
function getMockSheetsClient() returns sheets:Client|error {
    return test:mock(sheets:Client);
}

@test:Config {}
function testPostClaimRejectsInvalidClaim() returns error? {
    json invalidClaim = {date: "2026-09-01", category: "Entertainment", description: "Concert", amount: 25};
    http:Response response = check testClaimsClient->post("/", invalidClaim);
    test:assertEquals(response.statusCode, 400, msg = "expected a bad request for an unknown category");

    json responseBody = check response.getJsonPayload();
    map<json> responseBodyMap = <map<json>>responseBody;
    test:assertEquals(responseBodyMap["message"], "category must be one of: Travel, Meals, Office, Other",
            msg = "unexpected rejection message");
}

@test:Config {}
function testPostClaimRecordsValidClaim() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("appendValue").thenReturn(<sheets:ValueRange>{
        rowPosition: 12,
        values: [],
        a1Range: {sheetName}
    });

    json validClaim = {date: "2026-09-01", category: "Travel", description: "Taxi", amount: 45.50};
    http:Response response = check testClaimsClient->post("/", validClaim);
    test:assertEquals(response.statusCode, 201, msg = "expected the claim to be recorded");

    ClaimConfirmation confirmation = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(confirmation.message, "claim recorded", msg = "unexpected confirmation message");
    test:assertEquals(confirmation.rowNumber, 12, msg = "unexpected row number in confirmation");
}

@test:Config {}
function testPostClaimReturnsGenericMessageWhenSheetWriteFails() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("appendValue").thenReturn(error("permission denied for spreadsheet xyz"));

    json validClaim = {date: "2026-09-01", category: "Travel", description: "Taxi", amount: 45.50};
    http:Response response = check testClaimsClient->post("/", validClaim);
    test:assertEquals(response.statusCode, 500, msg = "expected a server error when the sheet write fails");

    json responseBody = check response.getJsonPayload();
    map<json> responseBodyMap = <map<json>>responseBody;
    test:assertEquals(responseBodyMap["message"], "could not record the claim, please retry",
            msg = "the response must not leak upstream error details");
    test:assertFalse(responseBodyMap.hasKey("spreadsheetId"), msg = "the response must never include the spreadsheet id");
}

@test:Config {}
function testGetSummaryComputesTotalsAndSkipsBadRows() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("getRange").thenReturn(<sheets:Range>{
        a1Notation: "A2:D",
        values: [
            ["2026-09-01", "Travel", "Taxi", 100d],
            ["2026-09-02", "Meals", "Lunch", 20d],
            ["2026-09-03", "Travel", "bad row", "not-a-number"],
            ["2026-09-04", "Meals", "Dinner", 30d]
        ]
    });

    http:Response response = check testClaimsClient->get("/summary");
    test:assertEquals(response.statusCode, 200, msg = "expected a successful summary response");

    ClaimsSummary summary = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(summary.totalsByCategory.get("Travel"), 100d, msg = "unexpected Travel total");
    test:assertEquals(summary.totalsByCategory.get("Meals"), 50d, msg = "unexpected Meals total");
    test:assertEquals(summary.totalsByCategory.get("Office"), 0d, msg = "unclaimed Office category should read as zero");
    test:assertEquals(summary.totalsByCategory.get("Other"), 0d, msg = "unclaimed Other category should read as zero");
    test:assertEquals(summary.overallTotal, 150d, msg = "unexpected overall total");
    test:assertEquals(summary.skippedRowCount, 1, msg = "expected the malformed row to be counted as skipped");
}

@test:Config {}
function testGetSummaryOnHeadersOnlySheetReturnsZeros() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("getRange").thenReturn(error("values not found in the response"));

    http:Response response = check testClaimsClient->get("/summary");
    test:assertEquals(response.statusCode, 200, msg = "a headers-only sheet must be a valid state, not a failure");

    ClaimsSummary summary = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(summary.overallTotal, 0d, msg = "expected a zero overall total for a headers-only sheet");
    test:assertEquals(summary.totalsByCategory.get("Travel"), 0d, msg = "expected zero Travel total for a headers-only sheet");
    test:assertEquals(summary.skippedRowCount, 0, msg = "expected no skipped rows for a headers-only sheet");
}

@test:Config {}
function testGetCategorySummaryRejectsUnknownCategory() returns error? {
    http:Response response = check testClaimsClient->get("/summary/Entertainment");
    test:assertEquals(response.statusCode, 400, msg = "expected a rejection for an unrecognized category");

    json responseBody = check response.getJsonPayload();
    map<json> responseBodyMap = <map<json>>responseBody;
    test:assertEquals(responseBodyMap["message"], "category must be one of: Travel, Meals, Office, Other",
            msg = "unexpected rejection message for an unknown category");
}

@test:Config {}
function testGetCategorySummaryReturnsTotalForKnownCategory() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("getRange").thenReturn(<sheets:Range>{
        a1Notation: "A2:D",
        values: [
            ["2026-09-01", "Meals", "Lunch", 20d],
            ["2026-09-02", "Meals", "bad-amount", "xyz"],
            ["2026-09-03", "Meals", "Dinner", 30d],
            ["2026-09-04", "Travel", "Taxi", 100d]
        ]
    });

    http:Response response = check testClaimsClient->get("/summary/Meals");
    test:assertEquals(response.statusCode, 200, msg = "expected a successful category summary response");

    CategorySummary summary = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(summary.category, "Meals", msg = "unexpected category in summary");
    test:assertEquals(summary.total, 50d, msg = "unexpected total for Meals");
    test:assertEquals(summary.skippedRowCount, 1, msg = "expected the malformed row to be counted as skipped");
}

@test:Config {}
function testPostSnapshotReplacesRatherThanAppends() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("getRange").thenReturn(<sheets:Range>{
        a1Notation: "A2:D",
        values: [
            ["2026-09-01", "Travel", "Taxi", 100d],
            ["2026-09-02", "Meals", "Lunch", 50d]
        ]
    });
    sheetsClientMock.when("getSheetByName").thenReturn(<sheets:Sheet>{properties: {title: snapshotSheetName}});
    sheetsClientMock.when("clearAllBySheetName").thenReturn(());
    sheetsClientMock.when("createOrUpdateRow").thenReturn(());

    http:Response firstResponse = check testClaimsClient->post("/snapshot", {});
    test:assertEquals(firstResponse.statusCode, 201, msg = "expected the first snapshot run to succeed");
    SnapshotResult firstResult = check (check firstResponse.getJsonPayload()).cloneWithType();

    http:Response secondResponse = check testClaimsClient->post("/snapshot", {});
    test:assertEquals(secondResponse.statusCode, 201, msg = "expected the second snapshot run to succeed");
    SnapshotResult secondResult = check (check secondResponse.getJsonPayload()).cloneWithType();

    test:assertEquals(firstResult.lines, secondResult.lines,
            msg = "running the snapshot twice in a row must produce identical contents, not doubled up totals");
    test:assertEquals(firstResult.lines.length(), 5, msg = "expected 4 category lines plus a grand total line");
    test:assertEquals(firstResult.lines[0], {label: "Travel", total: 100d}, msg = "unexpected Travel snapshot line");
    test:assertEquals(firstResult.lines[1], {label: "Meals", total: 50d}, msg = "unexpected Meals snapshot line");
    test:assertEquals(firstResult.lines[4], {label: "Grand Total", total: 150d}, msg = "unexpected grand total snapshot line");
}

@test:Config {}
function testPostSnapshotCreatesTabOnFirstRun() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("getRange").thenReturn(<sheets:Range>{
        a1Notation: "A2:D",
        values: []
    });
    sheetsClientMock.when("getSheetByName").thenReturn(error("sheet not found"));
    sheetsClientMock.when("addSheet").thenReturn(<sheets:Sheet>{properties: {title: snapshotSheetName}});
    sheetsClientMock.when("clearAllBySheetName").thenReturn(());
    sheetsClientMock.when("createOrUpdateRow").thenReturn(());

    http:Response response = check testClaimsClient->post("/snapshot", {});
    test:assertEquals(response.statusCode, 201, msg = "expected the snapshot to succeed by creating the tab");

    SnapshotResult result = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(result.message, "snapshot recorded", msg = "unexpected snapshot confirmation message");
    foreach SnapshotLine line in result.lines {
        if line.label != "Grand Total" {
            test:assertEquals(line.total, 0d, msg = "expected zero totals on an empty sheet");
        }
    }
}

@test:Config {}
function testPostSnapshotReturnsGenericMessageWhenWriteFails() returns error? {
    test:MockObject sheetsClientMock = test:prepare(sheetsClient);
    sheetsClientMock.when("getRange").thenReturn(<sheets:Range>{
        a1Notation: "A2:D",
        values: []
    });
    sheetsClientMock.when("getSheetByName").thenReturn(<sheets:Sheet>{properties: {title: snapshotSheetName}});
    sheetsClientMock.when("clearAllBySheetName").thenReturn(error("internal error, id: xyz, credentials invalid"));

    http:Response response = check testClaimsClient->post("/snapshot", {});
    test:assertEquals(response.statusCode, 500, msg = "expected a server error when the snapshot write fails");

    json responseBody = check response.getJsonPayload();
    map<json> responseBodyMap = <map<json>>responseBody;
    test:assertEquals(responseBodyMap["message"], "could not record the claim, please retry",
            msg = "the response must not leak upstream error details");
}
