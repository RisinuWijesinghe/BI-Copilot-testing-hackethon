import ballerinax/aws.dynamodb;
import ballerinax/aws.dynamodbstreams;

// Generic, caller-safe message. AWS error details, request identifiers, and credentials must never surface here.
const string CHANGE_FEED_SERVICE_UNREACHABLE = "unable to reach the change feed service";

# Marker error signalling that the requested table has no change feed.
type ChangeFeedNotFound distinct error;

# Retrieves the change feed (DynamoDB Streams) entries for every table in the account.
# Iterates the full account-wide table listing, page by page, and describes each table to
# determine whether it has a change feed enabled.
#
# + return - the list of change feed entries, or an error if AWS could not be reached
function getChangeFeedEntries() returns ChangeFeedEntry[]|error {
    stream<string, dynamodb:Error?> tableNames = check dynamoDbClient->listTables();

    ChangeFeedEntry[] changeFeedEntries = [];
    check from string tableName in tableNames
        do {
            dynamodb:TableDescription tableDescription = check dynamoDbClient->describeTable(tableName);
            dynamodb:StreamSpecification? streamSpecification = tableDescription?.StreamSpecification;
            if streamSpecification is dynamodb:StreamSpecification && streamSpecification.StreamEnabled {
                string? streamId = tableDescription?.LastDecreaseDateTimeatestStreamArn;
                string? streamLabel = tableDescription?.LatestStreamLabel;
                if streamId is string && streamLabel is string {
                    changeFeedEntries.push({
                        tableName,
                        streamId,
                        streamLabel
                    });
                }
            }
        };
    return changeFeedEntries;
}

# Retrieves the full change feed detail for a single table: its lifecycle status, the kind of item data each
# change record carries, its primary key attributes, and its current shard composition.
#
# + tableName - the name of the table to look up
# + return - the change feed detail, a `ChangeFeedNotFound` error if the table has no change feed, or a plain
# error if AWS could not be reached
function getChangeFeedDetail(string tableName) returns ChangeFeedDetail|ChangeFeedNotFound|error {
    dynamodb:TableDescription tableDescription = check dynamoDbClient->describeTable(tableName);

    dynamodb:StreamSpecification? streamSpecification = tableDescription?.StreamSpecification;
    string? streamId = tableDescription?.LastDecreaseDateTimeatestStreamArn;
    string? streamLabel = tableDescription?.LatestStreamLabel;
    if streamSpecification !is dynamodb:StreamSpecification || !streamSpecification.StreamEnabled
            || streamId !is string || streamLabel !is string {
        return error ChangeFeedNotFound(string `table '${tableName}' has no change feed`);
    }

    KeyAttribute[] keyAttributes = [];
    dynamodb:KeySchemaElement[]? keySchema = tableDescription?.KeySchema;
    if keySchema is dynamodb:KeySchemaElement[] {
        foreach dynamodb:KeySchemaElement keySchemaElement in keySchema {
            keyAttributes.push({
                attributeName: keySchemaElement.AttributeName,
                partitionKey: keySchemaElement.KeyType == dynamodb:HASH
            });
        }
    }

    [dynamodbstreams:StreamStatus, ShardSummary] [streamStatus, shardSummary] = check describeFullStream(streamId);
    ChangeFeedViewType viewType = mapViewType(streamSpecification?.StreamViewType);

    return {
        tableName,
        streamId,
        streamLabel,
        status: mapStreamStatus(streamStatus),
        viewType,
        keyAttributes,
        shards: shardSummary
    };
}

# Walks every page of shards for a change feed, summarizing how many are open (still accepting writes) versus
# closed, since busy feeds have more shards than fit in a single response. Also returns the stream's status, taken
# from the first page since it applies to the stream as a whole.
#
# + streamId - the ARN of the change feed
# + return - the stream status together with the shard summary, or an error if AWS could not be reached
function describeFullStream(string streamId) returns [dynamodbstreams:StreamStatus, ShardSummary]|error {
    int totalShards = 0;
    int openShards = 0;
    int closedShards = 0;
    dynamodbstreams:StreamStatus? streamStatus = ();

    string? exclusiveStartShardId = ();
    boolean hasMorePages = true;
    while hasMorePages {
        dynamodbstreams:DescribeStreamInput describeStreamInput = exclusiveStartShardId is string
            ? {streamArn: streamId, exclusiveStartShardId}
            : {streamArn: streamId};
        dynamodbstreams:StreamDescription description = check dynamoDbStreamsClient->describeStream(describeStreamInput);

        if streamStatus is () {
            streamStatus = description.streamStatus;
        }

        dynamodbstreams:Shard[]? shards = description.shards;
        if shards is dynamodbstreams:Shard[] {
            foreach dynamodbstreams:Shard shard in shards {
                totalShards += 1;
                dynamodbstreams:SequenceNumberRange? sequenceNumberRange = shard.sequenceNumberRange;
                boolean isClosed = sequenceNumberRange is dynamodbstreams:SequenceNumberRange
                    && sequenceNumberRange.endingSequenceNumber is string;
                if isClosed {
                    closedShards += 1;
                } else {
                    openShards += 1;
                }
            }
        }

        string? lastEvaluatedShardId = description.lastEvaluatedShardId;
        if lastEvaluatedShardId is string {
            exclusiveStartShardId = lastEvaluatedShardId;
        } else {
            hasMorePages = false;
        }
    }

    if streamStatus is () {
        return error("change feed status was not returned by AWS");
    }

    ShardSummary shardSummary = {
        totalShards,
        openShards,
        closedShards
    };
    return [streamStatus, shardSummary];
}

# Maps the AWS stream status to the change feed status vocabulary.
#
# + streamStatus - the AWS stream status
# + return - the corresponding change feed status
function mapStreamStatus(dynamodbstreams:StreamStatus streamStatus) returns ChangeFeedStatus {
    match streamStatus {
        dynamodbstreams:ENABLING => {
            return CHANGE_FEED_ENABLING;
        }
        dynamodbstreams:DISABLING => {
            return CHANGE_FEED_DISABLING;
        }
        dynamodbstreams:DISABLED => {
            return CHANGE_FEED_OFF;
        }
        _ => {
            return CHANGE_FEED_LIVE;
        }
    }
}

# Maps the AWS stream view type to the change feed view-type vocabulary, defaulting to `KEYS_ONLY` in the
# unexpected case that AWS omits it.
#
# + streamViewType - the AWS stream view type
# + return - the corresponding change feed view type
function mapViewType(dynamodbstreams:StreamViewType? streamViewType) returns ChangeFeedViewType {
    match streamViewType {
        dynamodbstreams:NEW_IMAGE => {
            return NEW_IMAGE;
        }
        dynamodbstreams:OLD_IMAGE => {
            return OLD_IMAGE;
        }
        dynamodbstreams:NEW_AND_OLD_IMAGES => {
            return NEW_AND_OLD_IMAGES;
        }
        _ => {
            return KEYS_ONLY;
        }
    }
}
