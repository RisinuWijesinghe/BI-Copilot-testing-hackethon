// Tracks the running picture of what the watcher has seen: how many placements, updates and removals, and for
// each shard, the identifier of the most recent change record handled from it. Safe to read and update
// concurrently from the watcher loop and the stats HTTP service.
isolated class WatcherStatsTracker {
    private int placements = 0;
    private int updates = 0;
    private int removals = 0;
    private final map<string> lastProcessedEventIdByShard = {};

    # Folds a single narrated change into the running picture.
    #
    # + narration - the narration to record
    # + shardId - the shard the change record was read from
    # + eventId - the identifier of the change record just handled
    isolated function recordChange(OrderChangeNarration narration, string shardId, string eventId) {
        lock {
            match narration.kind {
                ORDER_PLACED => {
                    self.placements += 1;
                }
                ORDER_STATUS_CHANGED => {
                    self.updates += 1;
                }
                ORDER_REMOVED => {
                    self.removals += 1;
                }
            }
            self.lastProcessedEventIdByShard[shardId] = eventId;
        }
    }

    # Takes a snapshot of the running picture, safe to render or serialize.
    #
    # + return - the current running picture
    isolated function snapshot() returns WatcherStats {
        lock {
            return {
                placements: self.placements,
                updates: self.updates,
                removals: self.removals,
                lastProcessedEventIdByShard: self.lastProcessedEventIdByShard.clone()
            };
        }
    }
}

final WatcherStatsTracker watcherStats = new;
