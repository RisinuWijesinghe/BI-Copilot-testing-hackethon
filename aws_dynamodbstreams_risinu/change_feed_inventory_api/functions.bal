import ballerinax/aws.dynamodbstreams;

// Generic, caller-safe message. AWS error details, request identifiers, and credentials must never surface here.
const string CHANGE_FEED_SERVICE_UNREACHABLE = "unable to reach the change feed service";

# Retrieves the full change feed detail for a single change feed: its lifecycle status, the kind of item data
# each change record carries, its primary key attributes, and its current shard composition.
#
# + streamId - the change feed identifier (stream ARN), as pasted from the AWS console
# + return - the change feed detail, or an error if AWS could not be reached
function getChangeFeedDetail(string streamId) returns ChangeFeedDetail|error {
    [dynamodbstreams:StreamDescription, dynamodbstreams:Shard[]] [description, shards] = check describeFullStream(streamId);
    ShardSummary shardSummary = computeShardSummary(shards);
    return buildChangeFeedDetail(streamId, description, shardSummary);
}

# Determines whether a change feed can be read from right now: it must be live, and a read position (shard
# iterator) must actually be obtainable for at least one of its shards.
#
# + streamId - the change feed identifier (stream ARN), as pasted from the AWS console
# + return - the readiness answer, or an error if AWS could not be reached
function getChangeFeedReadiness(string streamId) returns ChangeFeedReadiness|error {
    [dynamodbstreams:StreamDescription, dynamodbstreams:Shard[]] [description, shards] = check describeFullStream(streamId);

    ChangeFeedReadiness? notReady = checkLiveAndHasShards(description.streamStatus, shards);
    if notReady is ChangeFeedReadiness {
        return notReady;
    }

    boolean readableShardFound = check findReadableShard(streamId, shards);
    if readableShardFound {
        return {ready: true};
    }
    return {ready: false, reason: "could not obtain a read position for any shard"};
}

# Assembles the change feed detail response from an already-fetched stream description and shard summary.
# Pure function - performs no network calls - kept separate so it can be unit tested without AWS.
#
# + streamId - the change feed identifier (stream ARN)
# + description - the stream description already fetched from AWS
# + shardSummary - the shard summary already computed from the full shard listing
# + return - the assembled change feed detail, or an error if the description is missing required fields
function buildChangeFeedDetail(string streamId, dynamodbstreams:StreamDescription description, ShardSummary shardSummary)
        returns ChangeFeedDetail|error {
    string? tableName = description.tableName;
    string? streamLabel = description.streamLabel;
    if tableName is () || streamLabel is () {
        return error("change feed description was missing required fields");
    }
    return {
        tableName,
        streamId,
        streamLabel,
        status: mapStreamStatus(description.streamStatus),
        viewType: mapViewType(description.streamViewType),
        keyAttributes: extractKeyAttributes(description.keySchema),
        shards: shardSummary
    };
}

# Decides whether a feed is disqualified from being read right now based only on its status and shard list,
# without attempting to obtain a shard iterator. Pure function.
#
# + streamStatus - the stream's current status
# + shards - the full shard listing
# + return - a concrete not-ready answer if the feed is not live or has no shards, `()` if it qualifies for the
# iterator check
function checkLiveAndHasShards(dynamodbstreams:StreamStatus? streamStatus, dynamodbstreams:Shard[] shards) returns ChangeFeedReadiness? {
    ChangeFeedStatus status = mapStreamStatus(streamStatus);
    if status != CHANGE_FEED_LIVE {
        return {ready: false, reason: string `change feed is not live (currently ${status})`};
    }
    if shards.length() == 0 {
        return {ready: false, reason: "change feed has no shards"};
    }
    return ();
}

# Attempts to obtain a shard iterator for each shard in turn, stopping at the first success. This is the only
# network-calling piece of the readiness check and is intentionally kept thin.
#
# + streamId - the change feed identifier (stream ARN)
# + shards - the full shard listing
# + return - true if a read position could be obtained for at least one shard, false otherwise, or an error if
# AWS could not be reached
function findReadableShard(string streamId, dynamodbstreams:Shard[] shards) returns boolean|error {
    foreach dynamodbstreams:Shard shard in shards {
        string? shardId = shard.shardId;
        if shardId is string {
            string|dynamodbstreams:Error shardIterator = dynamoDbStreamsClient->getShardIterator({
                streamArn: streamId,
                shardId,
                shardIteratorType: dynamodbstreams:TRIM_HORIZON
            });
            if shardIterator is string {
                return true;
            }
        }
    }
    return false;
}

# Extracts the primary key attributes from a key schema, flagging the HASH attribute as the partition key.
# Pure function.
#
# + keySchema - the table's key schema, as returned in the stream description
# + return - the list of key attributes
function extractKeyAttributes(dynamodbstreams:KeySchemaElement[]? keySchema) returns KeyAttribute[] {
    KeyAttribute[] keyAttributes = [];
    if keySchema is dynamodbstreams:KeySchemaElement[] {
        foreach dynamodbstreams:KeySchemaElement keySchemaElement in keySchema {
            string? attributeName = keySchemaElement.attributeName;
            if attributeName is string {
                keyAttributes.push({
                    attributeName,
                    partitionKey: keySchemaElement.keyType == dynamodbstreams:HASH
                });
            }
        }
    }
    return keyAttributes;
}

# Walks every page of shards for a change feed, since busy feeds have more shards than fit in a single response.
# Returns the full stream description from the first page (status, view type, key schema, and table name apply
# to the stream as a whole) together with the complete shard listing.
#
# + streamId - the change feed identifier (stream ARN)
# + return - the stream description together with every shard, or an error if AWS could not be reached
function describeFullStream(string streamId) returns [dynamodbstreams:StreamDescription, dynamodbstreams:Shard[]]|error {
    dynamodbstreams:StreamDescription? firstDescription = ();
    dynamodbstreams:Shard[] allShards = [];

    string? exclusiveStartShardId = ();
    boolean hasMorePages = true;
    while hasMorePages {
        dynamodbstreams:DescribeStreamInput describeStreamInput = exclusiveStartShardId is string
            ? {streamArn: streamId, exclusiveStartShardId}
            : {streamArn: streamId};
        dynamodbstreams:StreamDescription description = check dynamoDbStreamsClient->describeStream(describeStreamInput);

        if firstDescription is () {
            firstDescription = description;
        }

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

    if firstDescription is () {
        return error("change feed description was not returned by AWS");
    }
    return [firstDescription, allShards];
}

# Counts how many shards are open (still accepting writes) versus closed. Pure function.
#
# + shards - the full shard listing
# + return - the shard summary
function computeShardSummary(dynamodbstreams:Shard[] shards) returns ShardSummary {
    int openShards = 0;
    int closedShards = 0;
    foreach dynamodbstreams:Shard shard in shards {
        if isShardClosed(shard) {
            closedShards += 1;
        } else {
            openShards += 1;
        }
    }
    return {
        totalShards: shards.length(),
        openShards,
        closedShards
    };
}

# A shard is closed once it has an ending sequence number. Pure function.
#
# + shard - the shard to inspect
# + return - true if the shard is closed
function isShardClosed(dynamodbstreams:Shard shard) returns boolean {
    dynamodbstreams:SequenceNumberRange? sequenceNumberRange = shard.sequenceNumberRange;
    return sequenceNumberRange is dynamodbstreams:SequenceNumberRange && sequenceNumberRange.endingSequenceNumber is string;
}

# Maps the AWS stream status to the change feed status vocabulary. Pure function.
#
# + streamStatus - the AWS stream status
# + return - the corresponding change feed status
function mapStreamStatus(dynamodbstreams:StreamStatus? streamStatus) returns ChangeFeedStatus {
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
# unexpected case that AWS omits it. Pure function.
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
