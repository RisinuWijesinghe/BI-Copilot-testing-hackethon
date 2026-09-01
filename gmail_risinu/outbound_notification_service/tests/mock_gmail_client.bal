import ballerinax/googleapis.gmail;

// Isolated mutable flag controlling send failure behavior across test cases,
// guarded by `lock` so the mock client class can remain `isolated`.
isolated boolean mockFailSend = false;

isolated function setMockFailSend(boolean shouldFail) {
    lock {
        mockFailSend = shouldFail;
    }
}

isolated function getMockFailSend() returns boolean {
    lock {
        return mockFailSend;
    }
}

// A fake Gmail client used in tests to avoid any real network/credential calls.
// It implements the same resource functions used by the service: sending a
// message and fetching the mailbox profile.
public isolated client class MockGmailClient {

    isolated resource function post users/[string userId]/messages/send(gmail:MessageRequest payload, gmail:Xgafv? xgafv = (), string? access_token = (), gmail:Alt? alt = (), string? callback = (), string? fields = (), string? 'key = (), string? oauth_token = (), boolean? prettyPrint = (), string? quotaUser = (), string? upload_protocol = (), string? uploadType = ()) returns gmail:Message|error {
        boolean shouldFail = getMockFailSend();
        if shouldFail {
            return error("simulated upstream Gmail failure");
        }
        return {
            threadId: "mock-thread-id",
            id: "mock-message-id"
        };
    }

    isolated resource function get users/[string userId]/profile(gmail:Xgafv? xgafv = (), string? access_token = (), gmail:Alt? alt = (), string? callback = (), string? fields = (), string? 'key = (), string? oauth_token = (), boolean? prettyPrint = (), string? quotaUser = (), string? upload_protocol = (), string? uploadType = ()) returns gmail:Profile|error {
        return {
            emailAddress: "team@example.com"
        };
    }
}
