import ballerina/http;
import ballerina/log;

service /change\-feeds on new http:Listener(servicePort) {

    # Retrieves the change feed detail for a single feed: its lifecycle status, what item data each change
    # record carries, its primary key attributes, and its current shard composition.
    #
    # + streamId - the change feed identifier (stream ARN), as pasted from the AWS console
    # + return - the change feed detail, a 400 if the identifier is missing or blank, or a 502 if AWS could not
    # be reached
    resource function get .(string streamId) returns ChangeFeedDetail|http:BadRequest|http:BadGateway {
        if streamId.trim().length() == 0 {
            ChangeFeedBadRequestError errorBody = {message: "streamId must not be blank"};
            return <http:BadRequest>{body: errorBody};
        }

        ChangeFeedDetail|error changeFeedDetail = getChangeFeedDetail(streamId);
        if changeFeedDetail is error {
            log:printError("failed to retrieve DynamoDB change feed detail from AWS", changeFeedDetail, streamId = streamId);
            ChangeFeedServiceError errorBody = {message: CHANGE_FEED_SERVICE_UNREACHABLE};
            return <http:BadGateway>{body: errorBody};
        }
        return changeFeedDetail;
    }

    # Answers whether a change feed can be read from right now: it must be live, and a read position must
    # actually be obtainable for at least one of its shards.
    #
    # + streamId - the change feed identifier (stream ARN), as pasted from the AWS console
    # + return - the readiness answer, a 400 if the identifier is missing or blank, or a 502 if AWS could not be
    # reached
    resource function get readiness(string streamId) returns ChangeFeedReadiness|http:BadRequest|http:BadGateway {
        if streamId.trim().length() == 0 {
            ChangeFeedBadRequestError errorBody = {message: "streamId must not be blank"};
            return <http:BadRequest>{body: errorBody};
        }

        ChangeFeedReadiness|error readiness = getChangeFeedReadiness(streamId);
        if readiness is error {
            log:printError("failed to determine DynamoDB change feed readiness from AWS", readiness, streamId = streamId);
            ChangeFeedServiceError errorBody = {message: CHANGE_FEED_SERVICE_UNREACHABLE};
            return <http:BadGateway>{body: errorBody};
        }
        return readiness;
    }
}
