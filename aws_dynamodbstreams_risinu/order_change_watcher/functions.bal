import ballerina/log;
import ballerina/time;
import ballerinax/aws.dynamodb;
import ballerinax/aws.dynamodbstreams;

// A record that carries no event identifier is not expected in practice, but stats tracking still needs a
// stand-in value in that case rather than failing.
const string UNKNOWN_EVENT_ID = "unknown";

# Looks up the latest change feed (stream) ARN for the Orders table, if one is currently enabled.
#
# + tableName - name of the table to inspect
# + return - the stream ARN if a change feed is enabled, `()` if the table has no change feed enabled, or an
# error if AWS could not be reached
function resolveOrdersStreamArn(string tableName) returns string?|error {
    dynamodb:Client dynamoDbClient = check getDynamoDbClient();
    dynamodb:TableDescription tableDescription = check dynamoDbClient->describeTable(tableName);
    dynamodb:StreamSpecification? streamSpecification = tableDescription?.StreamSpecification;
    if streamSpecification is () || !streamSpecification.StreamEnabled {
        return ();
    }
    string? latestStreamArn = check tableDescription["LatestStreamArn"].ensureType();
    if latestStreamArn is () {
        return ();
    }
    return latestStreamArn;
}

# Walks every page of shards for the change feed, since a busy feed can have more shards than fit in a single
# response.
#
# + streamArn - the change feed identifier (stream ARN)
# + return - the complete shard listing, or an error if AWS could not be reached
function listAllShards(string streamArn) returns dynamodbstreams:Shard[]|error {
    dynamodbstreams:Client dynamoDbStreamsClient = check getDynamoDbStreamsClient();
    dynamodbstreams:Shard[] allShards = [];
    string? exclusiveStartShardId = ();
    boolean hasMorePages = true;
    while hasMorePages {
        dynamodbstreams:DescribeStreamInput describeStreamInput = exclusiveStartShardId is string
            ? {streamArn, exclusiveStartShardId}
            : {streamArn};
        dynamodbstreams:StreamDescription description = check dynamoDbStreamsClient->describeStream(describeStreamInput);

        dynamodbstreams:Shard[]? shards = description.shards;
        if shards is dynamodbstreams:Shard[] {
            foreach dynamodbstreams:Shard shard in shards {
                allShards.push(shard);
            }
        }

        string? lastEvaluatedShardId = description.lastEvaluatedShardId;
        if lastEvaluatedShardId is string {
            exclusiveStartShardId = lastEvaluatedShardId;
        } else {
            hasMorePages = false;
        }
    }
    return allShards;
}

# Obtains a shard iterator positioned after the newest record already on the shard, so that only changes
# happening from this moment onwards are reported - this is a long-running service, not a backfill.
#
# + streamArn - the change feed identifier (stream ARN)
# + shardId - the shard to obtain a read position for
# + return - the shard iterator, or an error if AWS could not be reached
function openShardFromLatest(string streamArn, string shardId) returns string|error {
    dynamodbstreams:Client dynamoDbStreamsClient = check getDynamoDbStreamsClient();
    return dynamoDbStreamsClient->getShardIterator({
        streamArn,
        shardId,
        shardIteratorType: dynamodbstreams:LATEST
    });
}

# Extracts the string value of a named attribute from a change record image.
#
# + image - the item image (keys, new image, or old image) to read from
# + attributeName - name of the attribute to extract
# + return - the attribute's string value, or `()` if the attribute is absent or is not a string
function extractStringAttribute(map<dynamodbstreams:AttributeValue>? image, string attributeName) returns string? {
    if image is () {
        return ();
    }
    dynamodbstreams:AttributeValue? attributeValue = image[attributeName];
    if attributeValue is () {
        return ();
    }
    return attributeValue?.s;
}

# Recognizes statuses used by internal tests, so they can be kept out of the running picture.
#
# + status - the status value to check
# + return - true if this status is an internal test marker
function isTestStatus(string status) returns boolean {
    return status.startsWith(TEST_STATUS_PREFIX);
}

# Narrates a single change record into a ready-to-print description of what happened to an order.
# A record that is missing the attributes the watcher needs is not a fatal error - it is reported as a
# warning by the caller and simply skipped.
#
# + changeRecord - the change record to narrate
# + return - the narration, or `()` if the record was missing the attributes the watcher needs
function narrateChangeRecord(dynamodbstreams:Record changeRecord) returns OrderChangeNarration? {
    dynamodbstreams:StreamRecord? streamRecord = changeRecord.dynamodb;
    dynamodbstreams:OperationType? eventName = changeRecord.eventName;
    if streamRecord is () || eventName is () {
        return ();
    }

    string? orderId = extractStringAttribute(streamRecord.keys, ORDER_ID_ATTRIBUTE);
    if orderId is () {
        return ();
    }

    match eventName {
        dynamodbstreams:INSERT => {
            string? newStatus = extractStringAttribute(streamRecord.newImage, STATUS_ATTRIBUTE);
            if newStatus is () {
                return ();
            }
            if isTestStatus(newStatus) {
                log:printDebug("skipping order with an internal test status marker", orderId = orderId, status = newStatus);
                return ();
            }
            return {kind: ORDER_PLACED, orderId, newStatus};
        }
        dynamodbstreams:MODIFY => {
            string? previousStatus = extractStringAttribute(streamRecord.oldImage, STATUS_ATTRIBUTE);
            string? newStatus = extractStringAttribute(streamRecord.newImage, STATUS_ATTRIBUTE);
            if previousStatus is () || newStatus is () {
                return ();
            }
            if isTestStatus(previousStatus) || isTestStatus(newStatus) {
                log:printDebug("skipping order with an internal test status marker", orderId = orderId,
                        previousStatus = previousStatus, newStatus = newStatus);
                return ();
            }
            return {kind: ORDER_STATUS_CHANGED, orderId, previousStatus, newStatus};
        }
        dynamodbstreams:REMOVE => {
            string? previousStatus = extractStringAttribute(streamRecord.oldImage, STATUS_ATTRIBUTE);
            if previousStatus is string && isTestStatus(previousStatus) {
                log:printDebug("skipping order with an internal test status marker", orderId = orderId,
                        previousStatus = previousStatus);
                return ();
            }
            if previousStatus is () {
                return {kind: ORDER_REMOVED, orderId};
            }
            return {kind: ORDER_REMOVED, orderId, previousStatus};
        }
        _ => {
            return ();
        }
    }
}

# Renders a narration into the single line printed for it.
#
# + narration - the narration to render
# + return - the line to print
function renderNarration(OrderChangeNarration narration) returns string {
    string orderId = narration.orderId;
    match narration.kind {
        ORDER_PLACED => {
            return string `Order ${orderId} was placed with status ${narration?.newStatus ?: "unknown"}`;
        }
        ORDER_STATUS_CHANGED => {
            return string `Order ${orderId} moved from ${narration?.previousStatus ?: "unknown"} to ${narration?.newStatus ?: "unknown"}`;
        }
        ORDER_REMOVED => {
            string? previousStatus = narration?.previousStatus;
            return previousStatus is string
                ? string `Order ${orderId} is gone (was ${previousStatus})`
                : string `Order ${orderId} is gone`;
        }
    }
    return string `Order ${orderId} changed`;
}

# Reads whatever records are currently available at a shard's iterator and narrates each one, warning about
# and skipping any record that is missing the attributes the watcher needs instead of treating it as fatal.
#
# + shardId - the shard the iterator belongs to, recorded against each change handled from it
# + shardIterator - the shard iterator to read from
# + return - the next shard iterator to continue reading from (absent once the shard is exhausted) together
# with the number of records that were read, or an error if AWS could not be reached
function pollShardOnce(string shardId, string shardIterator) returns [string?, int]|error {
    dynamodbstreams:Client dynamoDbStreamsClient = check getDynamoDbStreamsClient();
    dynamodbstreams:GetRecordsOutput result = check dynamoDbStreamsClient->getRecords({shardIterator});
    dynamodbstreams:Record[]? records = result.records;
    if records is dynamodbstreams:Record[] {
        foreach dynamodbstreams:Record changeRecord in records {
            OrderChangeNarration? narration = narrateChangeRecord(changeRecord);
            if narration is () {
                log:printWarn("skipping change record missing expected order attributes",
                        eventId = changeRecord?.eventID, eventName = changeRecord.eventName);
                continue;
            }
            string line = renderNarration(narration);
            log:printInfo(line);
            string eventId = changeRecord?.eventID ?: UNKNOWN_EVENT_ID;
            watcherStats.recordChange(narration, shardId, eventId);
        }
        return [result.nextShardIterator, records.length()];
    }
    return [result.nextShardIterator, 0];
}

# The current wall-clock time, in seconds since the epoch.
#
# + return - the current time in seconds
function nowInSeconds() returns decimal {
    return <decimal>time:utcNow()[0];
}
