import ballerina/http;
import ballerina/test;
import ballerinax/googleapis.gmail;

@test:Mock {
    functionName: "initializeGmailClient"
}
isolated function getMockGmailClient() returns gmail:Client|error {
    return test:mock(gmail:Client, new MockGmailClient());
}

final http:Client testClient = check new (string `http://localhost:${servicePort}/triage`);

// Every test starts from a clean, empty fake mailbox with no failure injection.
// Cleanup batches need no explicit reset: each test's cleanups get their own
// freshly generated identifiers, so leftovers from other tests are never addressed.
@test:BeforeEach
function beforeEach() {
    resetFakeMailbox();
}

@test:Config {}
function testUnreadSweepEmptyInboxIsSuccessfulEmptyResult() returns error? {
    http:Response response = check testClient->get("/unread");
    test:assertEquals(response.statusCode, 200, msg = "empty inbox should be a successful empty result");
    UnreadMessageEntry[] entries = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(entries.length(), 0, msg = "no unread messages should mean an empty list");
}

@test:Config {}
function testUnreadSweepReturnsPreviewNotBody() returns error? {
    addFakeMessage({
        id: "msg-1",
        'from: "Alice <alice@example.com>",
        subject: "Hello there",
        snippet: "This is a short preview of the message",
        date: "Mon, 1 Sep 2026 10:00:00 +0000",
        labelIds: ["INBOX", "UNREAD"]
    });

    http:Response response = check testClient->get("/unread");
    test:assertEquals(response.statusCode, 200, msg = "expected 200 for unread sweep");
    UnreadMessageEntry[] entries = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(entries.length(), 1, msg = "expected exactly one unread message");
    test:assertEquals(entries[0].'from, "Alice <alice@example.com>", msg = "sender should be reported");
    test:assertEquals(entries[0].subject, "Hello there", msg = "subject should be reported");
    test:assertEquals(entries[0].preview, "This is a short preview of the message", msg = "preview should match the snippet");
}

@test:Config {}
function testUnreadSweepFailsGenericallyWhenMailboxUnreachable() returns error? {
    setOperationFailing("listMessages", true);
    http:Response response = check testClient->get("/unread");
    setOperationFailing("listMessages", false);

    test:assertEquals(response.statusCode, 500, msg = "expected 500 when the mailbox cannot be reached");
    ErrorDetails errorDetails = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(errorDetails.message, "triage is unavailable", msg = "failure message must be generic");
    test:assertFalse(errorDetails.message.includes("simulated"), msg = "upstream error text must never leak");
}

@test:Config {}
function testFilingSweepCreatesFoldersAndFilesByKeywordAndDomain() returns error? {
    addFakeMessage({
        id: "msg-billing",
        'from: "Billing Team <billing@vendor.com>",
        subject: "Your invoice is ready",
        snippet: "Invoice attached",
        date: "Mon, 1 Sep 2026 09:00:00 +0000",
        labelIds: ["INBOX", "UNREAD"]
    });
    addFakeMessage({
        id: "msg-bugs",
        'from: "QA <qa@example.com>",
        subject: "App crash on login",
        snippet: "Crash report",
        date: "Mon, 1 Sep 2026 09:05:00 +0000",
        labelIds: ["INBOX", "UNREAD"]
    });
    addFakeMessage({
        id: "msg-sales",
        'from: "Prospect <prospect@example.com>",
        subject: "Requesting a demo",
        snippet: "Can we schedule a demo",
        date: "Mon, 1 Sep 2026 09:10:00 +0000",
        labelIds: ["INBOX", "UNREAD"]
    });
    addFakeMessage({
        id: "msg-other",
        'from: "Newsletter <news@example.com>",
        subject: "Weekly digest",
        snippet: "Here is your digest",
        date: "Mon, 1 Sep 2026 09:15:00 +0000",
        labelIds: ["INBOX", "UNREAD"]
    });

    http:Response response = check testClient->post("/file", ());
    test:assertEquals(response.statusCode, 200, msg = "expected 200 for filing sweep");
    FilingSweepResult result = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(result.filed.length(), 4, msg = "all four messages should be filed");

    map<Category> categoryByMessageId = {};
    foreach FiledMessage filedMessage in result.filed {
        categoryByMessageId[filedMessage.messageId] = filedMessage.category;
    }
    test:assertEquals(categoryByMessageId.get("msg-billing"), "BILLING", msg = "invoice email should be filed under billing");
    test:assertEquals(categoryByMessageId.get("msg-bugs"), "BUGS", msg = "crash email should be filed under bugs");
    test:assertEquals(categoryByMessageId.get("msg-sales"), "SALES", msg = "demo request should be filed under sales");
    test:assertEquals(categoryByMessageId.get("msg-other"), "EVERYTHING_ELSE", msg = "unmatched email should be filed under everything-else");

    // Confirm the sweep actually tagged and marked read: nothing left in the unread inbox.
    http:Response unreadResponse = check testClient->get("/unread");
    UnreadMessageEntry[] remainingUnread = check (check unreadResponse.getJsonPayload()).cloneWithType();
    test:assertEquals(remainingUnread.length(), 0, msg = "filed messages should no longer be unread inbox mail");
}

@test:Config {}
function testRepeatFilingSweepDoesNothing() returns error? {
    addFakeMessage({
        id: "msg-1",
        'from: "Someone <someone@example.com>",
        subject: "Random subject",
        snippet: "preview",
        date: "Mon, 1 Sep 2026 09:00:00 +0000",
        labelIds: ["INBOX", "UNREAD"]
    });

    http:Response firstRun = check testClient->post("/file", ());
    test:assertEquals(firstRun.statusCode, 200, msg = "expected 200 for first filing sweep");
    FilingSweepResult firstResult = check (check firstRun.getJsonPayload()).cloneWithType();
    test:assertEquals(firstResult.filed.length(), 1, msg = "first run should file the one message");

    http:Response secondRun = check testClient->post("/file", ());
    test:assertEquals(secondRun.statusCode, 200, msg = "expected 200 for second filing sweep");
    FilingSweepResult secondResult = check (check secondRun.getJsonPayload()).cloneWithType();
    test:assertEquals(secondResult.filed.length(), 0, msg = "second run should find nothing left to file");

    http:Response backlogResponse = check testClient->get("/backlog");
    CategoryBacklog[] backlog = check (check backlogResponse.getJsonPayload()).cloneWithType();
    int everythingElseCount = 0;
    foreach CategoryBacklog categoryBacklog in backlog {
        if categoryBacklog.category == "EVERYTHING_ELSE" {
            everythingElseCount = categoryBacklog.count;
        }
    }
    test:assertEquals(everythingElseCount, 1, msg = "the folder should still hold exactly the one filed message, not a duplicate");
}

@test:Config {}
function testFilingSweepStopsWhenFolderCreationFailsPartway() returns error? {
    addFakeMessage({
        id: "msg-1",
        'from: "Someone <someone@example.com>",
        subject: "Random subject",
        snippet: "preview",
        date: "Mon, 1 Sep 2026 09:00:00 +0000",
        labelIds: ["INBOX", "UNREAD"]
    });
    // Billing and bugs folders get created fine; sales fails, stopping setup before
    // any filing happens.
    setFailCreateLabelNamed("sales");

    http:Response response = check testClient->post("/file", ());
    setFailCreateLabelNamed(());

    test:assertEquals(response.statusCode, 400, msg = "expected 400 when folder setup fails");
    ErrorDetails errorDetails = check (check response.getJsonPayload()).cloneWithType();
    test:assertTrue(errorDetails.message.includes("sales"), msg = "failure should name the category whose folder failed");

    // Nothing should have been filed: the message is still unread in the inbox.
    http:Response unreadResponse = check testClient->get("/unread");
    UnreadMessageEntry[] remainingUnread = check (check unreadResponse.getJsonPayload()).cloneWithType();
    test:assertEquals(remainingUnread.length(), 1, msg = "no message should be filed when folder setup fails partway");
}

@test:Config {}
function testFilingSweepFailsGenericallyWhenMailboxUnreachable() returns error? {
    setOperationFailing("listLabels", true);
    http:Response response = check testClient->post("/file", ());
    setOperationFailing("listLabels", false);

    test:assertEquals(response.statusCode, 500, msg = "expected 500 when the mailbox cannot be reached");
    ErrorDetails errorDetails = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(errorDetails.message, "triage is unavailable", msg = "failure message must be generic");
}

@test:Config {}
function testCleanupMovesFiledMessagesToBinAndBacklogDrops() returns error? {
    addFakeMessage({
        id: "msg-1",
        'from: "Billing <billing@vendor.com>",
        subject: "Invoice due",
        snippet: "preview",
        date: "Mon, 1 Sep 2026 09:00:00 +0000",
        labelIds: ["INBOX", "UNREAD"]
    });
    http:Response fileResponse = check testClient->post("/file", ());
    test:assertEquals(fileResponse.statusCode, 200, msg = "expected 200 for filing sweep");

    http:Response cleanupResponse = check testClient->post("/categories/BILLING/cleanup", ());
    test:assertEquals(cleanupResponse.statusCode, 200, msg = "expected 200 for cleanup");
    CleanupResult cleanupResult = check (check cleanupResponse.getJsonPayload()).cloneWithType();
    test:assertEquals(cleanupResult.category, "BILLING", msg = "cleanup should report the requested category");
    test:assertEquals(cleanupResult.messageIds.length(), 1, msg = "cleanup should move exactly the one billing message");
    test:assertEquals(cleanupResult.messageIds[0], "msg-1", msg = "cleanup should move the billing message");

    http:Response backlogResponse = check testClient->get("/backlog");
    CategoryBacklog[] backlog = check (check backlogResponse.getJsonPayload()).cloneWithType();
    int billingCount = -1;
    foreach CategoryBacklog categoryBacklog in backlog {
        if categoryBacklog.category == "BILLING" {
            billingCount = categoryBacklog.count;
        }
    }
    test:assertEquals(billingCount, 0, msg = "billing backlog should be empty after cleanup");
}

@test:Config {}
function testUndoRestoresExactlyThatCleanupsMessages() returns error? {
    addFakeMessage({
        id: "msg-1",
        'from: "Billing <billing@vendor.com>",
        subject: "Invoice due",
        snippet: "preview",
        date: "Mon, 1 Sep 2026 09:00:00 +0000",
        labelIds: ["INBOX", "UNREAD"]
    });
    addFakeMessage({
        id: "msg-2",
        'from: "Billing <billing@vendor.com>",
        subject: "Payment received",
        snippet: "preview",
        date: "Mon, 1 Sep 2026 09:05:00 +0000",
        labelIds: ["INBOX", "UNREAD"]
    });
    http:Response fileResponse = check testClient->post("/file", ());
    test:assertEquals(fileResponse.statusCode, 200, msg = "expected 200 for filing sweep");

    // First cleanup moves both billing messages to the bin.
    http:Response firstCleanupResponse = check testClient->post("/categories/BILLING/cleanup", ());
    CleanupResult firstCleanup = check (check firstCleanupResponse.getJsonPayload()).cloneWithType();
    test:assertEquals(firstCleanup.messageIds.length(), 2, msg = "first cleanup should move both billing messages");

    // A second cleanup on the same, now-empty category moves nothing.
    http:Response secondCleanupResponse = check testClient->post("/categories/BILLING/cleanup", ());
    CleanupResult secondCleanup = check (check secondCleanupResponse.getJsonPayload()).cloneWithType();
    test:assertEquals(secondCleanup.messageIds.length(), 0, msg = "second cleanup should find nothing left to move");

    // Undoing the first cleanup restores exactly its two messages, not whatever the
    // (empty) second cleanup moved.
    http:Response undoResponse = check testClient->post(string `/cleanups/${firstCleanup.cleanupId}/undo`, ());
    test:assertEquals(undoResponse.statusCode, 200, msg = "expected 200 for undo");
    UndoResult undoResult = check (check undoResponse.getJsonPayload()).cloneWithType();
    test:assertEquals(undoResult.messageIds.length(), 2, msg = "undo should restore exactly the first cleanup's two messages");

    http:Response backlogResponse = check testClient->get("/backlog");
    CategoryBacklog[] backlog = check (check backlogResponse.getJsonPayload()).cloneWithType();
    int billingCount = -1;
    foreach CategoryBacklog categoryBacklog in backlog {
        if categoryBacklog.category == "BILLING" {
            billingCount = categoryBacklog.count;
        }
    }
    test:assertEquals(billingCount, 2, msg = "billing backlog should show both messages restored");
}

@test:Config {}
function testCleanupOnNonExistentCategoryIsNotFound() returns error? {
    // No filing sweep has run, so no category folders exist yet.
    http:Response response = check testClient->post("/categories/BILLING/cleanup", ());
    test:assertEquals(response.statusCode, 404, msg = "cleanup on a category with no folder should be not found");
}

@test:Config {}
function testUndoNeverCleanedUpIsNotFound() returns error? {
    http:Response response = check testClient->post("/cleanups/does-not-exist/undo", ());
    test:assertEquals(response.statusCode, 404, msg = "undoing an unknown cleanup should be not found");
}

@test:Config {}
function testBacklogReportsCountsWithoutSweeping() returns error? {
    addFakeMessage({
        id: "msg-1",
        'from: "Billing <billing@vendor.com>",
        subject: "Invoice due",
        snippet: "preview",
        date: "Mon, 1 Sep 2026 09:00:00 +0000",
        labelIds: ["INBOX", "UNREAD"]
    });
    addFakeMessage({
        id: "msg-2",
        'from: "QA <qa@example.com>",
        subject: "Crash report",
        snippet: "preview",
        date: "Mon, 1 Sep 2026 09:05:00 +0000",
        labelIds: ["INBOX", "UNREAD"]
    });

    http:Response fileResponse = check testClient->post("/file", ());
    test:assertEquals(fileResponse.statusCode, 200, msg = "expected 200 for filing sweep");

    http:Response backlogResponse = check testClient->get("/backlog");
    test:assertEquals(backlogResponse.statusCode, 200, msg = "expected 200 for backlog");
    CategoryBacklog[] backlog = check (check backlogResponse.getJsonPayload()).cloneWithType();
    test:assertEquals(backlog.length(), 4, msg = "backlog should report all four categories");

    map<int> countByCategory = {};
    foreach CategoryBacklog categoryBacklog in backlog {
        countByCategory[categoryBacklog.category] = categoryBacklog.count;
    }
    test:assertEquals(countByCategory.get("BILLING"), 1, msg = "billing backlog should be one");
    test:assertEquals(countByCategory.get("BUGS"), 1, msg = "bugs backlog should be one");
    test:assertEquals(countByCategory.get("SALES"), 0, msg = "sales backlog should be zero");
    test:assertEquals(countByCategory.get("EVERYTHING_ELSE"), 0, msg = "everything-else backlog should be zero");
}

@test:Config {}
function testBacklogFailsGenericallyWhenMailboxUnreachable() returns error? {
    setOperationFailing("listLabels", true);
    http:Response response = check testClient->get("/backlog");
    setOperationFailing("listLabels", false);

    test:assertEquals(response.statusCode, 500, msg = "expected 500 when the mailbox cannot be reached");
    ErrorDetails errorDetails = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(errorDetails.message, "triage is unavailable", msg = "failure message must be generic");
}
