import ballerinax/googleapis.gmail;

// A single message in the fake mailbox used by tests. Mirrors just the fields the
// service reads: headers (From/Subject), snippet, and the current label set.
type FakeMessage record {|
    string id;
    string 'from;
    string subject;
    string snippet;
    string date;
    string[] labelIds;
|};

// Names of operations whose failure can be injected by a test, simulating an
// unreachable mailbox, rejected credentials, or a folder creation failing partway.
type FailingOperation "listMessages"|"getMessage"|"listLabels"|"createLabel"|"modifyMessage"|"trashMessage"|"untrashMessage";

// Mutable state of the fake mailbox, guarded by `lock` so the mock client class
// can remain `isolated`. Reset before each test that needs a clean mailbox.
isolated FakeMessage[] fakeMessages = [];
isolated gmail:Label[] fakeLabels = [];
isolated int nextLabelSequence = 1;
isolated map<boolean> failingOperations = {};
// When set, createLabel fails only once this specific label name is created,
// simulating folder creation failing partway through the four categories.
isolated string? failCreateLabelNamed = ();

isolated function resetFakeMailbox() {
    lock {
        fakeMessages = [];
        fakeLabels = [];
        nextLabelSequence = 1;
        failingOperations = {};
        failCreateLabelNamed = ();
    }
}

isolated function addFakeMessage(FakeMessage message) {
    lock {
        fakeMessages.push(message.clone());
    }
}

isolated function setOperationFailing(FailingOperation operation, boolean shouldFail) {
    lock {
        failingOperations[operation] = shouldFail;
    }
}

isolated function setFailCreateLabelNamed(string? labelName) {
    lock {
        failCreateLabelNamed = labelName;
    }
}

isolated function isOperationFailing(FailingOperation operation) returns boolean {
    lock {
        return failingOperations[operation] ?: false;
    }
}

isolated function messageHasLabel(FakeMessage message, string labelId) returns boolean {
    foreach string labelId2 in message.labelIds {
        if labelId2 == labelId {
            return true;
        }
    }
    return false;
}

isolated function findFakeLabelIdByName(gmail:Label[] labels, string labelName) returns string? {
    foreach gmail:Label label in labels {
        string? name = label.name;
        if name is string && name.toLowerAscii() == labelName.toLowerAscii() {
            return label.id;
        }
    }
    return ();
}

// Very small interpreter for the subset of Gmail search syntax the service uses:
// "label:INBOX", "is:unread", "-in:trash", combined with spaces (AND semantics).
isolated function fakeMessageMatchesQuery(FakeMessage message, string query, gmail:Label[] labels) returns boolean {
    string[] terms = re ` +`.split(query.trim());
    foreach string term in terms {
        if term.length() == 0 {
            continue;
        }
        if term == "is:unread" {
            if !messageHasLabel(message, "UNREAD") {
                return false;
            }
        } else if term == "-in:trash" {
            if messageHasLabel(message, "TRASH") {
                return false;
            }
        } else if term.startsWith("label:") {
            string labelName = term.substring("label:".length());
            string? labelId = labelName == "INBOX" ? "INBOX" : findFakeLabelIdByName(labels, labelName);
            if labelId is () || !messageHasLabel(message, labelId) {
                return false;
            }
        }
        // Any other free-text search-phrase term is ignored by this fake: tests that
        // use a search phrase only check that it is passed through, not real matching.
    }
    return true;
}

// A fake Gmail client used in tests to avoid any real network/credential calls. It
// keeps a small in-memory mailbox (messages and labels) and implements exactly the
// resource functions the service uses.
public isolated client class MockGmailClient {

    isolated resource function get users/[string userId]/messages(gmail:Xgafv? xgafv = (), string? access_token = (), gmail:Alt? alt = (), string? callback = (), string? fields = (), string? 'key = (), string? oauth_token = (), boolean? prettyPrint = (), string? quotaUser = (), string? upload_protocol = (), string? uploadType = (), boolean? includeSpamTrash = (), string[]? labelIds = (), int? maxResults = (), string? pageToken = (), string? q = ()) returns gmail:ListMessagesResponse|error {
        if isOperationFailing("listMessages") {
            return error("simulated upstream Gmail failure");
        }
        string query = q ?: "";
        gmail:Message[] matches = [];
        lock {
            foreach FakeMessage message in fakeMessages {
                if fakeMessageMatchesQuery(message, query, fakeLabels) {
                    matches.push({id: message.id, threadId: message.id});
                }
            }
        }
        return {messages: matches};
    }

    isolated resource function get users/[string userId]/messages/[string id](gmail:Xgafv? xgafv = (), string? access_token = (), gmail:Alt? alt = (), string? callback = (), string? fields = (), string? 'key = (), string? oauth_token = (), boolean? prettyPrint = (), string? quotaUser = (), string? upload_protocol = (), string? uploadType = (), "metadata"|()|"minimal"|"full"|"raw" format = (), string[]? metadataHeaders = ()) returns gmail:Message|error {
        if isOperationFailing("getMessage") {
            return error("simulated upstream Gmail failure");
        }
        lock {
            foreach FakeMessage message in fakeMessages {
                if message.id == id {
                    map<string> headers = {"From": message.'from, "Subject": message.subject, "Date": message.date};
                    return {
                        id: message.id,
                        threadId: message.id,
                        snippet: message.snippet,
                        labelIds: message.labelIds.clone(),
                        payload: {partId: "0", headers: headers.clone()}
                    };
                }
            }
        }
        return error("message not found");
    }

    isolated resource function get users/[string userId]/labels(gmail:Xgafv? xgafv = (), string? access_token = (), gmail:Alt? alt = (), string? callback = (), string? fields = (), string? 'key = (), string? oauth_token = (), boolean? prettyPrint = (), string? quotaUser = (), string? upload_protocol = (), string? uploadType = ()) returns gmail:ListLabelsResponse|error {
        if isOperationFailing("listLabels") {
            return error("simulated upstream Gmail failure");
        }
        lock {
            return {labels: fakeLabels.clone()};
        }
    }

    isolated resource function post users/[string userId]/labels(gmail:Label payload, gmail:Xgafv? xgafv = (), string? access_token = (), gmail:Alt? alt = (), string? callback = (), string? fields = (), string? 'key = (), string? oauth_token = (), boolean? prettyPrint = (), string? quotaUser = (), string? upload_protocol = (), string? uploadType = ()) returns gmail:Label|error {
        if isOperationFailing("createLabel") {
            return error("simulated upstream Gmail failure");
        }
        string? labelName = payload.name;
        lock {
            if labelName is string && failCreateLabelNamed == labelName {
                return error("simulated folder creation failure");
            }
        }
        lock {
            string labelId = string `label-${nextLabelSequence}`;
            nextLabelSequence += 1;
            gmail:Label newLabel = {id: labelId, name: labelName ?: "", 'type: "user"};
            fakeLabels.push(newLabel.clone());
            return newLabel.clone();
        }
    }

    isolated resource function post users/[string userId]/messages/[string id]/modify(gmail:ModifyMessageRequest payload, gmail:Xgafv? xgafv = (), string? access_token = (), gmail:Alt? alt = (), string? callback = (), string? fields = (), string? 'key = (), string? oauth_token = (), boolean? prettyPrint = (), string? quotaUser = (), string? upload_protocol = (), string? uploadType = ()) returns gmail:Message|error {
        if isOperationFailing("modifyMessage") {
            return error("simulated upstream Gmail failure");
        }
        lock {
            foreach int i in 0 ..< fakeMessages.length() {
                if fakeMessages[i].id == id {
                    string[] labelIds = fakeMessages[i].labelIds.clone();
                    foreach string addLabelId in payload.addLabelIds ?: [] {
                        if labelIds.indexOf(addLabelId) is () {
                            labelIds.push(addLabelId);
                        }
                    }
                    string[] afterRemoval = [];
                    foreach string existingLabelId in labelIds {
                        boolean shouldRemove = false;
                        foreach string removeLabelId in payload.removeLabelIds ?: [] {
                            if existingLabelId == removeLabelId {
                                shouldRemove = true;
                            }
                        }
                        if !shouldRemove {
                            afterRemoval.push(existingLabelId);
                        }
                    }
                    fakeMessages[i].labelIds = afterRemoval;
                    return {id, threadId: id, labelIds: afterRemoval.clone()};
                }
            }
        }
        return error("message not found");
    }

    isolated resource function post users/[string userId]/messages/[string id]/trash(gmail:Xgafv? xgafv = (), string? access_token = (), gmail:Alt? alt = (), string? callback = (), string? fields = (), string? 'key = (), string? oauth_token = (), boolean? prettyPrint = (), string? quotaUser = (), string? upload_protocol = (), string? uploadType = ()) returns gmail:Message|error {
        if isOperationFailing("trashMessage") {
            return error("simulated upstream Gmail failure");
        }
        lock {
            foreach int i in 0 ..< fakeMessages.length() {
                if fakeMessages[i].id == id {
                    string[] labelIds = fakeMessages[i].labelIds.clone();
                    if labelIds.indexOf("TRASH") is () {
                        labelIds.push("TRASH");
                    }
                    fakeMessages[i].labelIds = labelIds;
                    return {id, threadId: id, labelIds: labelIds.clone()};
                }
            }
        }
        return error("message not found");
    }

    isolated resource function post users/[string userId]/messages/[string id]/untrash(gmail:Xgafv? xgafv = (), string? access_token = (), gmail:Alt? alt = (), string? callback = (), string? fields = (), string? 'key = (), string? oauth_token = (), boolean? prettyPrint = (), string? quotaUser = (), string? upload_protocol = (), string? uploadType = ()) returns gmail:Message|error {
        if isOperationFailing("untrashMessage") {
            return error("simulated upstream Gmail failure");
        }
        lock {
            foreach int i in 0 ..< fakeMessages.length() {
                if fakeMessages[i].id == id {
                    string[] labelIds = [];
                    foreach string labelId in fakeMessages[i].labelIds {
                        if labelId != "TRASH" {
                            labelIds.push(labelId);
                        }
                    }
                    fakeMessages[i].labelIds = labelIds;
                    return {id, threadId: id, labelIds: labelIds.clone()};
                }
            }
        }
        return error("message not found");
    }
}
