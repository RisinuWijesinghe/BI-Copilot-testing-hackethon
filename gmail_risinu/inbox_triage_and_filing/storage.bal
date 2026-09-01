// In-memory store of cleanup batches, keyed by cleanup identifier, so that undoing
// a specific cleanup restores exactly the messages that cleanup moved to the bin
// rather than everything currently sitting in the bin. A batch is removed once it
// has been undone, so undoing it again is reported as not found rather than a no-op.
final map<CleanupBatch> cleanupBatchStore = {};

function storeCleanupBatch(CleanupBatch batch) {
    cleanupBatchStore[batch.cleanupId] = batch;
}

function getCleanupBatch(string cleanupId) returns CleanupBatch? {
    return cleanupBatchStore[cleanupId];
}

function removeCleanupBatch(string cleanupId) {
    _ = cleanupBatchStore.removeIfHasKey(cleanupId);
}
