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

    # Moves every message currently filed under a category to the bin. The set of
    # messages moved is recorded against the returned cleanup identifier so it can
    # be undone precisely later.
    #
    # + category - the category to clean up
    # + return - the cleanup identifier and the messages moved (empty when the category
    # had nothing filed), not found when the category's folder does not exist, or a
    # generic failure when the mailbox could not be reached or the credentials were rejected
    resource function post categories/[Category category]/cleanup() returns CleanupResult|http:NotFound|http:InternalServerError {
        CleanupResult|CategoryNotFound|error result = cleanupCategory(category);
        if result is CategoryNotFound {
            return <http:NotFound>{body: {message: string `no folder found for category '${category}'`}};
        }
        if result is error {
            log:printError("category cleanup failed", result);
            return <http:InternalServerError>{body: {message: "triage is unavailable"}};
        }
        return result;
    }

    # Restores exactly the messages moved to the bin by a single earlier cleanup.
    #
    # + cleanupId - the cleanup identifier returned when that cleanup was performed
    # + return - the restored messages, not found when the identifier does not match any
    # recorded cleanup (never happened, or already undone), or a generic failure when the
    # mailbox could not be reached or the credentials were rejected
    resource function post cleanups/[string cleanupId]/undo() returns UndoResult|http:NotFound|http:InternalServerError {
        UndoResult|CleanupNotFound|error result = undoCleanup(cleanupId);
        if result is CleanupNotFound {
            return <http:NotFound>{body: {message: "no cleanup found for the given identifier"}};
        }
        if result is error {
            log:printError("cleanup undo failed", result);
            return <http:InternalServerError>{body: {message: "triage is unavailable"}};
        }
        return result;
    }

    # Reports the current backlog count for each of the four category folders,
    # without running a sweep.
    #
    # + return - the current count for each category, or a generic failure when the
    # mailbox could not be reached or the credentials were rejected
    resource function get backlog() returns CategoryBacklog[]|http:InternalServerError {
        CategoryBacklog[]|error result = currentBacklog();
        if result is error {
            log:printError("backlog count failed", result);
            return <http:InternalServerError>{body: {message: "triage is unavailable"}};
        }
        return result;
    }
}
