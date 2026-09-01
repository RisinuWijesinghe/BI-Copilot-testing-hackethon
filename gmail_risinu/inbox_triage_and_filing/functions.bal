import ballerinax/googleapis.gmail;

// Builds the Gmail search query for the unread sweep: always restricted to unread
// mail in the inbox, optionally narrowed further by a caller-supplied search phrase.
function buildUnreadQuery(string? searchPhrase) returns string {
    if searchPhrase is string && searchPhrase.trim().length() > 0 {
        return string `label:INBOX is:unread ${searchPhrase}`;
    }
    return "label:INBOX is:unread";
}

// Sweeps unread mail in the inbox, optionally narrowed by a search phrase, and
// returns one triaged entry per message. Any failure to reach the mailbox or a
// rejected credential is collapsed into a single generic error so that nothing
// from Gmail's own error surface ever reaches the caller.
function sweepUnreadMessages(string? searchPhrase) returns UnreadMessageEntry[]|error {
    string query = buildUnreadQuery(searchPhrase);

    gmail:ListMessagesResponse|error listResult = gmailClient->/users/me/messages(q = query);
    if listResult is error {
        return error("triage is unavailable");
    }

    gmail:Message[]? messageRefs = listResult.messages;
    if messageRefs is () {
        return [];
    }

    UnreadMessageEntry[] entries = [];
    foreach gmail:Message messageRef in messageRefs {
        gmail:Message|error fullMessage = gmailClient->/users/me/messages/[messageRef.id](
            format = "metadata",
            metadataHeaders = ["From", "Subject", "Date"]
        );
        if fullMessage is error {
            return error("triage is unavailable");
        }
        entries.push(toUnreadMessageEntry(fullMessage));
    }

    return entries;
}
