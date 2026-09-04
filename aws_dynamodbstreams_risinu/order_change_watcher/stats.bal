import ballerina/time;

// Tracks the running picture of what the watcher has seen: how many placements, updates and removals, how many
// orders are sitting in each status right now, and when the last change came through. Safe to read and update
// concurrently from the watcher loop and the stats HTTP service.
isolated class WatcherStatsTracker {
    private int placements = 0;
    private int updates = 0;
    private int removals = 0;
    private final map<int> ordersByStatus = {};
    private string? lastChangeAt = ();

    # Folds a single narrated change into the running picture.
    #
    # + narration - the narration to record
    isolated function recordChange(OrderChangeNarration narration) {
        lock {
            match narration.kind {
                ORDER_PLACED => {
                    self.placements += 1;
                    string? newStatus = narration.newStatus;
                    if newStatus is string {
                        int currentCount = self.ordersByStatus[newStatus] ?: 0;
                        self.ordersByStatus[newStatus] = currentCount + 1;
                    }
                }
                ORDER_STATUS_CHANGED => {
                    self.updates += 1;
                    string? previousStatus = narration.previousStatus;
                    if previousStatus is string {
                        int currentCount = self.ordersByStatus[previousStatus] ?: 0;
                        int updatedCount = currentCount - 1;
                        if updatedCount <= 0 {
                            _ = self.ordersByStatus.removeIfHasKey(previousStatus);
                        } else {
                            self.ordersByStatus[previousStatus] = updatedCount;
                        }
                    }
                    string? newStatus = narration.newStatus;
                    if newStatus is string {
                        int currentCount = self.ordersByStatus[newStatus] ?: 0;
                        self.ordersByStatus[newStatus] = currentCount + 1;
                    }
                }
                ORDER_EXPIRED|ORDER_DELETED => {
                    self.removals += 1;
                    string? previousStatus = narration.previousStatus;
                    if previousStatus is string {
                        int currentCount = self.ordersByStatus[previousStatus] ?: 0;
                        int updatedCount = currentCount - 1;
                        if updatedCount <= 0 {
                            _ = self.ordersByStatus.removeIfHasKey(previousStatus);
                        } else {
                            self.ordersByStatus[previousStatus] = updatedCount;
                        }
                    }
                }
            }
            self.lastChangeAt = time:utcToString(time:utcNow());
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
                ordersByStatus: self.ordersByStatus.clone(),
                lastChangeAt: self.lastChangeAt
            };
        }
    }
}

final WatcherStatsTracker watcherStats = new;
