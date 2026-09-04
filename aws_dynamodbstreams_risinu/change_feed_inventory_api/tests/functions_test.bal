import ballerina/test;
import ballerinax/aws.dynamodbstreams;

@test:Config {}
function testMapStreamStatusLive() {
    ChangeFeedStatus status = mapStreamStatus(dynamodbstreams:ENABLED);
    test:assertEquals(status, CHANGE_FEED_LIVE, msg = "ENABLED should map to live");
}

@test:Config {}
function testMapStreamStatusEnabling() {
    ChangeFeedStatus status = mapStreamStatus(dynamodbstreams:ENABLING);
    test:assertEquals(status, CHANGE_FEED_ENABLING, msg = "ENABLING should map to enabling");
}

@test:Config {}
function testMapStreamStatusDisabling() {
    ChangeFeedStatus status = mapStreamStatus(dynamodbstreams:DISABLING);
    test:assertEquals(status, CHANGE_FEED_DISABLING, msg = "DISABLING should map to disabling");
}

@test:Config {}
function testMapStreamStatusOff() {
    ChangeFeedStatus status = mapStreamStatus(dynamodbstreams:DISABLED);
    test:assertEquals(status, CHANGE_FEED_OFF, msg = "DISABLED should map to off");
}

@test:Config {}
function testMapStreamStatusDefaultsToLiveWhenMissing() {
    ChangeFeedStatus status = mapStreamStatus(());
    test:assertEquals(status, CHANGE_FEED_LIVE, msg = "missing status should default to live");
}

@test:Config {}
function testMapViewTypeKeysOnly() {
    ChangeFeedViewType viewType = mapViewType(dynamodbstreams:KEYS_ONLY);
    test:assertEquals(viewType, KEYS_ONLY, msg = "KEYS_ONLY should map to keys only");
}

@test:Config {}
function testMapViewTypeNewImage() {
    ChangeFeedViewType viewType = mapViewType(dynamodbstreams:NEW_IMAGE);
    test:assertEquals(viewType, NEW_IMAGE, msg = "NEW_IMAGE should map to new image");
}

@test:Config {}
function testMapViewTypeOldImage() {
    ChangeFeedViewType viewType = mapViewType(dynamodbstreams:OLD_IMAGE);
    test:assertEquals(viewType, OLD_IMAGE, msg = "OLD_IMAGE should map to old image");
}

@test:Config {}
function testMapViewTypeNewAndOldImages() {
    ChangeFeedViewType viewType = mapViewType(dynamodbstreams:NEW_AND_OLD_IMAGES);
    test:assertEquals(viewType, NEW_AND_OLD_IMAGES, msg = "NEW_AND_OLD_IMAGES should map to both images");
}

@test:Config {}
function testMapViewTypeDefaultsToKeysOnlyWhenMissing() {
    ChangeFeedViewType viewType = mapViewType(());
    test:assertEquals(viewType, KEYS_ONLY, msg = "missing view type should default to keys only");
}

@test:Config {}
function testIsShardClosedWhenEndingSequenceNumberPresent() {
    dynamodbstreams:Shard shard = {
        shardId: "shard-1",
        sequenceNumberRange: {startingSequenceNumber: "100", endingSequenceNumber: "200"}
    };
    test:assertTrue(isShardClosed(shard), msg = "a shard with an ending sequence number should be closed");
}

@test:Config {}
function testIsShardClosedWhenEndingSequenceNumberAbsent() {
    dynamodbstreams:Shard shard = {
        shardId: "shard-1",
        sequenceNumberRange: {startingSequenceNumber: "100"}
    };
    test:assertFalse(isShardClosed(shard), msg = "a shard without an ending sequence number should be open");
}

@test:Config {}
function testIsShardClosedWhenSequenceNumberRangeAbsent() {
    dynamodbstreams:Shard shard = {shardId: "shard-1"};
    test:assertFalse(isShardClosed(shard), msg = "a shard without a sequence number range should be open");
}

@test:Config {}
function testComputeShardSummaryCountsOpenAndClosedAcrossManyShards() {
    dynamodbstreams:Shard[] shards = [
        {shardId: "shard-1", sequenceNumberRange: {startingSequenceNumber: "1", endingSequenceNumber: "2"}},
        {shardId: "shard-2", sequenceNumberRange: {startingSequenceNumber: "3", endingSequenceNumber: "4"}},
        {shardId: "shard-3", sequenceNumberRange: {startingSequenceNumber: "5"}},
        {shardId: "shard-4"}
    ];
    ShardSummary summary = computeShardSummary(shards);
    test:assertEquals(summary.totalShards, 4, msg = "total shards should count every shard");
    test:assertEquals(summary.closedShards, 2, msg = "closed shard count should be correct");
    test:assertEquals(summary.openShards, 2, msg = "open shard count should be correct");
}

@test:Config {}
function testComputeShardSummaryWithNoShards() {
    ShardSummary summary = computeShardSummary([]);
    test:assertEquals(summary.totalShards, 0, msg = "total shards should be zero");
    test:assertEquals(summary.openShards, 0, msg = "open shards should be zero");
    test:assertEquals(summary.closedShards, 0, msg = "closed shards should be zero");
}

@test:Config {}
function testExtractKeyAttributesFlagsPartitionKey() {
    dynamodbstreams:KeySchemaElement[] keySchema = [
        {attributeName: "pk", keyType: dynamodbstreams:HASH},
        {attributeName: "sk", keyType: dynamodbstreams:RANGE}
    ];
    KeyAttribute[] keyAttributes = extractKeyAttributes(keySchema);
    test:assertEquals(keyAttributes.length(), 2, msg = "both key attributes should be extracted");
    test:assertEquals(keyAttributes[0], {attributeName: "pk", partitionKey: true}, msg = "HASH attribute should be the partition key");
    test:assertEquals(keyAttributes[1], {attributeName: "sk", partitionKey: false}, msg = "RANGE attribute should not be the partition key");
}

@test:Config {}
function testExtractKeyAttributesWithMissingKeySchema() {
    KeyAttribute[] keyAttributes = extractKeyAttributes(());
    test:assertEquals(keyAttributes.length(), 0, msg = "missing key schema should yield no key attributes");
}

@test:Config {}
function testBuildChangeFeedDetailAssemblesResponse() returns error? {
    dynamodbstreams:StreamDescription description = {
        tableName: "Orders",
        streamLabel: "2026-01-01T00:00:00.000",
        streamStatus: dynamodbstreams:ENABLED,
        streamViewType: dynamodbstreams:NEW_AND_OLD_IMAGES,
        keySchema: [{attributeName: "orderId", keyType: dynamodbstreams:HASH}]
    };
    ShardSummary shardSummary = {totalShards: 5, openShards: 3, closedShards: 2};
    string streamArn = "arn:aws:dynamodb:us-east-1:123456789012:table/Orders/stream/2026-01-01T00:00:00.000";

    ChangeFeedDetail detail = check buildChangeFeedDetail(streamArn, description, shardSummary);

    test:assertEquals(detail.tableName, "Orders", msg = "table name should be taken from the description");
    test:assertEquals(detail.streamId, streamArn, msg = "stream id should echo back the input identifier");
    test:assertEquals(detail.streamLabel, "2026-01-01T00:00:00.000", msg = "stream label should be taken from the description");
    test:assertEquals(detail.status, CHANGE_FEED_LIVE, msg = "status should be mapped");
    test:assertEquals(detail.viewType, NEW_AND_OLD_IMAGES, msg = "view type should be mapped");
    test:assertEquals(detail.keyAttributes, [{attributeName: "orderId", partitionKey: true}], msg = "key attributes should be extracted");
    test:assertEquals(detail.shards, shardSummary, msg = "shard summary should be passed through");
}

@test:Config {}
function testBuildChangeFeedDetailFailsWhenTableNameMissing() {
    dynamodbstreams:StreamDescription description = {
        streamLabel: "2026-01-01T00:00:00.000",
        streamStatus: dynamodbstreams:ENABLED
    };
    ChangeFeedDetail|error result = buildChangeFeedDetail("arn:aws:dynamodb:...", description, {totalShards: 0, openShards: 0, closedShards: 0});
    test:assertTrue(result is error, msg = "a description missing the table name should fail");
}

@test:Config {}
function testCheckLiveAndHasShardsWhenNotLive() {
    dynamodbstreams:Shard[] shards = [{shardId: "shard-1"}];
    ChangeFeedReadiness? result = checkLiveAndHasShards(dynamodbstreams:DISABLED, shards);
    test:assertTrue(result is ChangeFeedReadiness, msg = "a disabled feed should short-circuit to not ready");
    if result is ChangeFeedReadiness {
        test:assertFalse(result.ready, msg = "a disabled feed should not be ready");
        test:assertTrue(result?.reason is string, msg = "a reason should be present");
    }
}

@test:Config {}
function testCheckLiveAndHasShardsWhenLiveButNoShards() {
    ChangeFeedReadiness? result = checkLiveAndHasShards(dynamodbstreams:ENABLED, []);
    test:assertTrue(result is ChangeFeedReadiness, msg = "a live feed with no shards should short-circuit to not ready");
    if result is ChangeFeedReadiness {
        test:assertFalse(result.ready, msg = "a feed with no shards should not be ready");
        test:assertEquals(result?.reason, "change feed has no shards", msg = "the reason should explain there are no shards");
    }
}

@test:Config {}
function testCheckLiveAndHasShardsWhenLiveWithShards() {
    dynamodbstreams:Shard[] shards = [{shardId: "shard-1"}];
    ChangeFeedReadiness? result = checkLiveAndHasShards(dynamodbstreams:ENABLED, shards);
    test:assertTrue(result is (), msg = "a live feed with shards should proceed to the iterator check");
}
