import ballerina/http;
import ballerina/test;
import ballerinax/googleapis.gmail;

@test:Mock {
    functionName: "initializeGmailClient"
}
isolated function getMockGmailClient() returns gmail:Client|error {
    return test:mock(gmail:Client, new MockGmailClient());
}

final http:Client testClient = check new (string `http://localhost:${servicePort}/notifications`);

function buildRequestPayload(string[] to, string subject, string htmlBody, AttachmentReference[] attachments = [], InlineImageReference[] inlineImages = []) returns json {
    return {
        to,
        subject,
        htmlBody,
        attachments,
        inlineImages
    };
}

@test:Config {}
function testSendImmediatelyForInternalRecipient() returns error? {
    json payload = buildRequestPayload(["colleague@example.com"], "Internal notice", "<p>hello</p>");
    http:Response response = check testClient->post("/email", payload);
    test:assertEquals(response.statusCode, 200, msg = "expected 200 for immediate send");
    EmailNotificationResult result = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(result.status, "SENT", msg = "internal recipient should be sent immediately");
}

@test:Config {}
function testBadRequestEmptyRecipients() returns error? {
    json payload = buildRequestPayload([], "Subject", "<p>body</p>");
    http:Response response = check testClient->post("/email", payload);
    test:assertEquals(response.statusCode, 400, msg = "expected 400 for empty recipients");
    ErrorDetails errorDetails = check (check response.getJsonPayload()).cloneWithType();
    test:assertTrue(errorDetails.message.includes("recipients"), msg = "error message should mention recipients");
}

@test:Config {}
function testBadRequestInvalidEmail() returns error? {
    json payload = buildRequestPayload(["not-an-email"], "Subject", "<p>body</p>");
    http:Response response = check testClient->post("/email", payload);
    test:assertEquals(response.statusCode, 400, msg = "expected 400 for invalid email");
    ErrorDetails errorDetails = check (check response.getJsonPayload()).cloneWithType();
    test:assertTrue(errorDetails.message.includes("recipients"), msg = "error message should mention recipients");
}

@test:Config {}
function testBadRequestAttachmentMissing() returns error? {
    json payload = buildRequestPayload(["colleague@example.com"], "Subject", "<p>body</p>", [{fileName: "missing.txt"}]);
    http:Response response = check testClient->post("/email", payload);
    test:assertEquals(response.statusCode, 400, msg = "expected 400 for missing attachment file");
    ErrorDetails errorDetails = check (check response.getJsonPayload()).cloneWithType();
    test:assertTrue(errorDetails.message.includes("missing.txt"), msg = "error message should name the missing file");
}

@test:Config {}
function testBadRequestAttachmentTooLarge() returns error? {
    json payload = buildRequestPayload(["colleague@example.com"], "Subject", "<p>body</p>", [{fileName: "large.txt"}]);
    http:Response response = check testClient->post("/email", payload);
    test:assertEquals(response.statusCode, 400, msg = "expected 400 for oversized attachment file");
    ErrorDetails errorDetails = check (check response.getJsonPayload()).cloneWithType();
    test:assertTrue(errorDetails.message.includes("large.txt"), msg = "error message should name the oversized file");
}

@test:Config {}
function testValidAttachmentSentSuccessfully() returns error? {
    json payload = buildRequestPayload(["colleague@example.com"], "Subject", "<p>body</p>", [{fileName: "small.txt"}]);
    http:Response response = check testClient->post("/email", payload);
    test:assertEquals(response.statusCode, 200, msg = "expected 200 for a valid attachment");
    EmailNotificationResult result = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(result.status, "SENT", msg = "internal recipient with a valid attachment should be sent");
}

string parkedNotificationId = "";

@test:Config {}
function testParkedForExternalRecipient() returns error? {
    json payload = buildRequestPayload(["outsider@elsewhere.com"], "External notice", "<p>hello outside</p>");
    http:Response response = check testClient->post("/email", payload);
    test:assertEquals(response.statusCode, 200, msg = "expected 200 for parked notification");
    EmailNotificationResult result = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(result.status, "PARKED", msg = "external recipient should be parked for review");
    parkedNotificationId = result.notificationId;
}

@test:Config {dependsOn: [testParkedForExternalRecipient]}
function testListParked() returns error? {
    http:Response response = check testClient->get("/parked");
    test:assertEquals(response.statusCode, 200, msg = "expected 200 listing parked notifications");
    ParkedNotificationSummary[] summaries = check (check response.getJsonPayload()).cloneWithType();
    boolean found = false;
    foreach ParkedNotificationSummary summary in summaries {
        if summary.notificationId == parkedNotificationId {
            found = true;
        }
    }
    test:assertTrue(found, msg = "parked notification should appear in the list");
}

@test:Config {dependsOn: [testListParked]}
function testGetParkedDetail() returns error? {
    http:Response response = check testClient->get("/parked/" + parkedNotificationId);
    test:assertEquals(response.statusCode, 200, msg = "expected 200 for parked detail");
    ParkedNotificationDetail detail = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(detail.notificationId, parkedNotificationId, msg = "detail should match requested id");
    test:assertEquals(detail.subject, "External notice", msg = "detail subject should match original");
}

@test:Config {dependsOn: [testGetParkedDetail]}
function testReviseParked() returns error? {
    json revision = buildRequestPayload(["outsider@elsewhere.com"], "Revised external notice", "<p>revised body</p>");
    http:Response response = check testClient->put("/parked/" + parkedNotificationId, revision);
    test:assertEquals(response.statusCode, 200, msg = "expected 200 for revision");
    ParkedNotificationDetail detail = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(detail.notificationId, parkedNotificationId, msg = "revision should keep the same identifier");
    test:assertEquals(detail.subject, "Revised external notice", msg = "revision should update the subject");

    http:Response getResponse = check testClient->get("/parked/" + parkedNotificationId);
    test:assertEquals(getResponse.statusCode, 200, msg = "revised notification should still be parked");
}

@test:Config {}
function testReviseNotFound() returns error? {
    json revision = buildRequestPayload(["outsider@elsewhere.com"], "Subject", "<p>body</p>");
    http:Response response = check testClient->put("/parked/does-not-exist", revision);
    test:assertEquals(response.statusCode, 404, msg = "revising an unknown notification should be not found");
}

@test:Config {dependsOn: [testReviseParked]}
function testApproveParked() returns error? {
    http:Response response = check testClient->post("/parked/" + parkedNotificationId + "/approve", ());
    test:assertEquals(response.statusCode, 200, msg = "expected 200 on approval");
    ApprovalResult result = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(result.notificationId, parkedNotificationId, msg = "approval should return the same identifier");

    http:Response getResponse = check testClient->get("/parked/" + parkedNotificationId);
    test:assertEquals(getResponse.statusCode, 404, msg = "approved notification should no longer be parked");
}

@test:Config {dependsOn: [testApproveParked]}
function testApproveAlreadySentIsNotFound() returns error? {
    http:Response response = check testClient->post("/parked/" + parkedNotificationId + "/approve", ());
    test:assertEquals(response.statusCode, 404, msg = "approving an already-sent notification should be not found, not a second send");
}

@test:Config {}
function testApproveUnknownIsNotFound() returns error? {
    http:Response response = check testClient->post("/parked/does-not-exist/approve", ());
    test:assertEquals(response.statusCode, 404, msg = "approving an unknown notification should be not found");
}

string discardNotificationId = "";

@test:Config {}
function testDiscardParked() returns error? {
    json payload = buildRequestPayload(["outsider2@elsewhere.com"], "To be discarded", "<p>body</p>");
    http:Response createResponse = check testClient->post("/email", payload);
    test:assertEquals(createResponse.statusCode, 200, msg = "expected 200 for parked notification");
    EmailNotificationResult created = check (check createResponse.getJsonPayload()).cloneWithType();
    discardNotificationId = created.notificationId;

    http:Response deleteResponse = check testClient->delete("/parked/" + discardNotificationId);
    test:assertEquals(deleteResponse.statusCode, 204, msg = "expected 204 on discard");

    http:Response getResponse = check testClient->get("/parked/" + discardNotificationId);
    test:assertEquals(getResponse.statusCode, 404, msg = "discarded notification should be actually removed");
}

@test:Config {dependsOn: [testDiscardParked]}
function testDiscardUnknownIsNotFound() returns error? {
    http:Response response = check testClient->delete("/parked/" + discardNotificationId);
    test:assertEquals(response.statusCode, 404, msg = "discarding an already-discarded notification should be not found");
}

@test:Config {}
function testGmailSendFailureReturnsGenericError() returns error? {
    setMockFailSend(true);
    json payload = buildRequestPayload(["colleague@example.com"], "Subject", "<p>body</p>");
    http:Response response = check testClient->post("/email", payload);
    setMockFailSend(false);

    test:assertEquals(response.statusCode, 500, msg = "expected 500 when Gmail send fails");
    ErrorDetails errorDetails = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(errorDetails.message, "couldn't send the notification email", msg = "failure message must be generic");
    test:assertFalse(errorDetails.message.includes("simulated upstream Gmail failure"), msg = "upstream error text must never leak");
}

@test:Config {dependsOn: [testSendImmediatelyForInternalRecipient, testValidAttachmentSentSuccessfully, testApproveAlreadySentIsNotFound, testApproveUnknownIsNotFound, testDiscardUnknownIsNotFound, testGmailSendFailureReturnsGenericError]}
function testStatsReflectCounts() returns error? {
    http:Response response = check testClient->get("/stats");
    test:assertEquals(response.statusCode, 200, msg = "expected 200 for stats");
    NotificationStats stats = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(stats.parkedCount, 0, msg = "no notifications should remain parked");
    test:assertEquals(stats.sentCount, 3, msg = "three notifications should have been sent");
    test:assertEquals(stats.discardedCount, 1, msg = "one notification should have been discarded");
}
