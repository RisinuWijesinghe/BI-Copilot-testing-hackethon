import ballerina/lang.runtime;
import ballerina/log;
import ballerinax/aws.dynamodbstreams;

// Tracks the read position and liveness of a single shard while the watcher is running.
type ShardCursor record {|
    string shardId;
    string? shardIterator;
|};

public function main() returns error? {
    string? streamArn = check resolveOrdersStreamArn(ordersTableName);
    if streamArn is () {
        log:printInfo(string `the "${ordersTableName}" table has no change feed enabled - nothing to watch, exiting`);
        return;
    }

    log:printInfo(string `watching change feed for table "${ordersTableName}"`, streamArn = streamArn);

    dynamodbstreams:Shard[] shards = check listAllShards(streamArn);
    if shards.length() == 0 {
        log:printInfo("the change feed currently has no shards - nothing to watch, exiting");
        return;
    }

    ShardCursor[] cursors = [];
    foreach dynamodbstreams:Shard shard in shards {
        string? shardId = shard.shardId;
        if shardId is () {
            continue;
        }
        string|error shardIterator = openShardFromTrimHorizon(streamArn, shardId);
        if shardIterator is error {
            log:printWarn("could not open shard from the start of the retained feed, skipping it",
                    shardId = shardId);
            continue;
        }
        cursors.push({shardId, shardIterator});
    }

    if cursors.length() == 0 {
        log:printInfo("no shard could be opened for reading - nothing to watch, exiting");
        return;
    }

    decimal lastActivityAt = nowInSeconds();
    boolean anyShardStillOpen = true;
    while anyShardStillOpen {
        boolean recordsSeenThisSweep = false;
        anyShardStillOpen = false;

        foreach ShardCursor cursor in cursors {
            string? shardIterator = cursor.shardIterator;
            if shardIterator is () {
                continue;
            }
            anyShardStillOpen = true;

            [string?, int]|error pollResult = pollShardOnce(shardIterator);
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
        if recordsSeenThisSweep {
            lastActivityAt = currentTime;
        } else if anyShardStillOpen && currentTime - lastActivityAt >= idleTimeoutSeconds {
            log:printInfo(string `the feed has been quiet for ${idleTimeoutSeconds} seconds - finishing`);
            return;
        }

        if anyShardStillOpen && !recordsSeenThisSweep {
            runtime:sleep(pollIntervalSeconds);
        }
    }

    log:printInfo("every shard in the feed has been fully read - finishing");
}
