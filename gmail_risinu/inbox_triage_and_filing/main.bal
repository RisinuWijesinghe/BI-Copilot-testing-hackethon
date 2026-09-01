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

    # Sweeps unread mail in the inbox and files each message into one of four
    # category folders (billing, bugs, sales, everything-else) based on configurable
    # subject-keyword and sender-domain rules, then tags and marks each message read
    # so a later sweep finds nothing left to do. The category folders are created
    # first if any are missing; if that setup fails, nothing is filed.
    #
    # + return - the messages filed and the category each landed in (empty when there
    # was nothing unread to file), a bad request naming the category whose folder could
    # not be set up, or a generic failure when the mailbox could not be reached or the
    # credentials were rejected
    resource function post file() returns FilingSweepResult|http:BadRequest|http:InternalServerError {
        FilingSweepResult|FilingSetupFailure|error result = sweepAndFileUnreadMessages();
        if result is FilingSetupFailure {
            log:printError(string `category folder setup failed for '${result.category}'`);
            return <http:BadRequest>{body: {message: result.message}};
        }
        if result is error {
            log:printError("unread mail filing sweep failed", result);
            return <http:InternalServerError>{body: {message: "triage is unavailable"}};
        }
        return result;
    }
}
