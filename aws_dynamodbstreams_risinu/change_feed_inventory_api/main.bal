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
}
