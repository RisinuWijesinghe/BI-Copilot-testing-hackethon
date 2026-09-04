import ballerina/http;
import ballerina/log;

service /change\-feeds on new http:Listener(servicePort) {

    # Lists every DynamoDB table in the account that has a change feed (DynamoDB Streams) enabled.
    #
    # + return - the list of change feed entries, or a 502 if AWS could not be reached
    resource function get .() returns ChangeFeedEntry[]|http:BadGateway {
        ChangeFeedEntry[]|error changeFeedEntries = getChangeFeedEntries();
        if changeFeedEntries is error {
            log:printError("failed to retrieve DynamoDB change feed inventory from AWS", changeFeedEntries);
            ChangeFeedServiceError errorBody = {message: CHANGE_FEED_SERVICE_UNREACHABLE};
            return <http:BadGateway>{body: errorBody};
        }
        return changeFeedEntries;
    }

    # Retrieves the change feed detail for a single table: its lifecycle status, what item data each change
    # record carries, its primary key attributes, and its current shard composition.
    #
    # + tableName - the name of the table to look up
    # + return - the change feed detail, a 400 if the table name is missing or blank, a 404 if the table has no
    # change feed, or a 502 if AWS could not be reached
    resource function get [string tableName]() returns ChangeFeedDetail|http:BadRequest|http:NotFound|http:BadGateway {
        if tableName.trim().length() == 0 {
            ChangeFeedBadRequestError errorBody = {message: "table name must not be blank"};
            return <http:BadRequest>{body: errorBody};
        }

        ChangeFeedDetail|ChangeFeedNotFound|error changeFeedDetail = getChangeFeedDetail(tableName);
        if changeFeedDetail is ChangeFeedNotFound {
            ChangeFeedNotFoundError errorBody = {message: changeFeedDetail.message()};
            return <http:NotFound>{body: errorBody};
        }
        if changeFeedDetail is error {
            log:printError("failed to retrieve DynamoDB change feed detail from AWS", changeFeedDetail, tableName = tableName);
            ChangeFeedServiceError errorBody = {message: CHANGE_FEED_SERVICE_UNREACHABLE};
            return <http:BadGateway>{body: errorBody};
        }
        return changeFeedDetail;
    }
}
