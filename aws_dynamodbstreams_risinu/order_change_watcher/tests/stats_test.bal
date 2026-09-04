import ballerina/test;

@test:Config {}
function testStatsTrackerCountsPlacementAndTracksLastEventPerShard() {
    WatcherStatsTracker tracker = new;
    tracker.recordChange({kind: ORDER_PLACED, orderId: "order-1", newStatus: "PLACED"}, "shard-1", "evt-1");

    WatcherStats stats = tracker.snapshot();
    test:assertEquals(stats.placements, 1, msg = "a placement should be counted");
    test:assertEquals(stats.updates, 0, msg = "updates should not change on a placement");
    test:assertEquals(stats.removals, 0, msg = "removals should not change on a placement");
    test:assertEquals(stats.lastProcessedEventIdByShard, {"shard-1": "evt-1"},
            msg = "the most recent event id for the shard should be recorded");
}

@test:Config {}
function testStatsTrackerCountsUpdate() {
    WatcherStatsTracker tracker = new;
    tracker.recordChange({kind: ORDER_STATUS_CHANGED, orderId: "order-1", previousStatus: "PLACED", newStatus: "SHIPPED"},
            "shard-1", "evt-2");

    WatcherStats stats = tracker.snapshot();
    test:assertEquals(stats.placements, 0, msg = "placements should not change on an update");
    test:assertEquals(stats.updates, 1, msg = "an update should be counted");
    test:assertEquals(stats.removals, 0, msg = "removals should not change on an update");
}

@test:Config {}
function testStatsTrackerCountsRemoval() {
    WatcherStatsTracker tracker = new;
    tracker.recordChange({kind: ORDER_REMOVED, orderId: "order-1", previousStatus: "SHIPPED"}, "shard-1", "evt-3");

    WatcherStats stats = tracker.snapshot();
    test:assertEquals(stats.placements, 0, msg = "placements should not change on a removal");
    test:assertEquals(stats.updates, 0, msg = "updates should not change on a removal");
    test:assertEquals(stats.removals, 1, msg = "a removal should be counted");
}

@test:Config {}
function testStatsTrackerAccumulatesTotalsAcrossManyChanges() {
    WatcherStatsTracker tracker = new;
    tracker.recordChange({kind: ORDER_PLACED, orderId: "order-1", newStatus: "PLACED"}, "shard-1", "evt-1");
    tracker.recordChange({kind: ORDER_PLACED, orderId: "order-2", newStatus: "PLACED"}, "shard-1", "evt-2");
    tracker.recordChange({kind: ORDER_STATUS_CHANGED, orderId: "order-1", previousStatus: "PLACED", newStatus: "SHIPPED"},
            "shard-1", "evt-3");
    tracker.recordChange({kind: ORDER_REMOVED, orderId: "order-2", previousStatus: "PLACED"}, "shard-1", "evt-4");

    WatcherStats stats = tracker.snapshot();
    test:assertEquals(stats.placements, 2, msg = "both placements should be counted");
    test:assertEquals(stats.updates, 1, msg = "the single update should be counted");
    test:assertEquals(stats.removals, 1, msg = "the single removal should be counted");
    test:assertEquals(stats.lastProcessedEventIdByShard, {"shard-1": "evt-4"},
            msg = "the shard should reflect only the most recent event id");
}

@test:Config {}
function testStatsTrackerTracksLastEventIndependentlyPerShard() {
    WatcherStatsTracker tracker = new;
    tracker.recordChange({kind: ORDER_PLACED, orderId: "order-1", newStatus: "PLACED"}, "shard-1", "evt-1");
    tracker.recordChange({kind: ORDER_PLACED, orderId: "order-2", newStatus: "PLACED"}, "shard-2", "evt-9");
    tracker.recordChange({kind: ORDER_STATUS_CHANGED, orderId: "order-1", previousStatus: "PLACED", newStatus: "SHIPPED"},
            "shard-1", "evt-2");

    WatcherStats stats = tracker.snapshot();
    test:assertEquals(stats.lastProcessedEventIdByShard, {"shard-1": "evt-2", "shard-2": "evt-9"},
            msg = "each shard should track its own most recent event id, unaffected by other shards");
}

@test:Config {}
function testStatsTrackerSnapshotStartsEmpty() {
    WatcherStatsTracker tracker = new;
    WatcherStats stats = tracker.snapshot();
    test:assertEquals(stats.placements, 0, msg = "a fresh tracker should have no placements");
    test:assertEquals(stats.updates, 0, msg = "a fresh tracker should have no updates");
    test:assertEquals(stats.removals, 0, msg = "a fresh tracker should have no removals");
    test:assertEquals(stats.lastProcessedEventIdByShard, {}, msg = "a fresh tracker should have no shard progress");
}
