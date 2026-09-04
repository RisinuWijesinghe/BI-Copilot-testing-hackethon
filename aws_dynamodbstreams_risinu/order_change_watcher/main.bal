import ballerina/lang.runtime;
import ballerina/log;
import ballerinax/aws.dynamodbstreams;

// Tracks the read position of a single shard while the watcher is running.
type ShardCursor record {|
    string shardId;
    string? shardIterator;
|};

public function main() returns error? {
    return watchOrdersChangeFeed();
}

# Runs the watcher loop forever: resolves the change feed and reads every shard, picking up replacements
# created by reshards along the way. This is a long-running service - it only reports changes that happen
# from the moment it starts, and keeps running until it is stopped from the outside.
#
# + return - an error if AWS could not be reached while setting up
function watchOrdersChangeFeed() returns error? {
    string? streamArn = check resolveOrdersStreamArn(ordersTableName);
    if streamArn is () {
        log:printInfo(string `the "${ordersTableName}" table has no change feed enabled - nothing to watch, exiting`);
        return;
    }

    log:printInfo(string `watching change feed for table "${ordersTableName}"`, streamArn = streamArn);

    ShardCursor[] cursors = [];
    map<boolean> knownShardIds = {};
    int openedShardCount = check discoverAndOpenNewShards(streamArn, cursors, knownShardIds);

    if openedShardCount == 0 {
        log:printInfo("no shard could be opened for reading - nothing to watch, exiting");
        return;
    }

    decimal lastShardDiscoveryAt = nowInSeconds();
    while true {
        boolean recordsSeenThisSweep = false;

        foreach ShardCursor cursor in cursors {
            string? shardIterator = cursor.shardIterator;
            if shardIterator is () {
                continue;
            }

            [string?, int]|error pollResult = pollShardOnce(cursor.shardId, shardIterator);
            if pollResult is error {
                log:printWarn("could not read from shard, will retry on the next sweep",
                        shardId = cursor.shardId);
                continue;
            }

            string? nextShardIterator = pollResult[0];
            int recordCount = pollResult[1];
            cursor.shardIterator = nextShardIterator;
            if recordCount > 0 {
                recordsSeenThisSweep = true;
            }
        }

        decimal currentTime = nowInSeconds();

        // The feed re-partitions as the table's traffic shifts: shards close and are replaced by new ones.
        // Re-checking the topology periodically means a reshard is picked up promptly instead of the watcher
        // appearing to just go quiet.
        if currentTime - lastShardDiscoveryAt >= shardDiscoveryIntervalSeconds {
            int|error newShardCount = discoverAndOpenNewShards(streamArn, cursors, knownShardIds);
            lastShardDiscoveryAt = currentTime;
            if newShardCount is error {
                log:printWarn("could not check the feed for new shards, will retry on the next sweep");
            } else if newShardCount > 0 {
                log:printInfo(string `feed was re-partitioned - now watching ${newShardCount} additional shard(s)`);
                recordsSeenThisSweep = true;
            }
        }

        if !recordsSeenThisSweep {
            runtime:sleep(pollIntervalSeconds);
        }
    }
}

# Looks up the feed's current shard topology and opens a read position, from this point onwards, for every
# shard not already being tracked. This is how both the initial set of shards and any replacements created by
# a later reshard are picked up.
#
# + streamArn - the change feed identifier (stream ARN)
# + cursors - the read positions being tracked so far; newly opened shards are appended to this list
# + knownShardIds - the shard identifiers already being tracked; newly opened shards are added to this set
# + return - the number of newly opened shards, or an error if AWS could not be reached
function discoverAndOpenNewShards(string streamArn, ShardCursor[] cursors, map<boolean> knownShardIds)
        returns int|error {
    dynamodbstreams:Shard[] shards = check listAllShards(streamArn);
    int openedCount = 0;
    foreach dynamodbstreams:Shard shard in shards {
        string? shardId = shard.shardId;
        if shardId is () || knownShardIds.hasKey(shardId) {
            continue;
        }
        knownShardIds[shardId] = true;

        string|error shardIterator = openShardFromLatest(streamArn, shardId);
        if shardIterator is error {
            log:printWarn("could not open shard for reading, skipping it", shardId = shardId);
            continue;
        }
        cursors.push({shardId, shardIterator});
        openedCount += 1;
    }
    return openedCount;
}
