import ballerina/http;
import ballerina/log;

service /triage on new http:Listener(servicePort) {

    # Sweeps unread mail in the inbox, optionally narrowed by a search phrase, and
    # returns one entry per message with the sender, subject, arrival time and a
    # one-line preview. Full message bodies are never included in the response.
    #
    # + searchPhrase - an optional phrase to further narrow the unread messages searched
    # + return - one entry per unread message (empty when the inbox has none), or a
    # generic failure when the mailbox could not be reached or the credentials were rejected
    resource function get unread(string? searchPhrase = ()) returns UnreadMessageEntry[]|http:InternalServerError {
        UnreadMessageEntry[]|error entries = sweepUnreadMessages(searchPhrase);
        if entries is error {
            log:printError("unread mail triage sweep failed", entries);
            return <http:InternalServerError>{body: {message: "triage is unavailable"}};
        }
        return entries;
    }
}
