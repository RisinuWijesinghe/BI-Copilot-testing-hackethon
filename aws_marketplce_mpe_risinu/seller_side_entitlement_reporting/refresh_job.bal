import ballerina/log;
import ballerina/task;
import ballerinax/aws.marketplace.mpe;

# Background job that refreshes the entitlement snapshot for every configured product. A failure
# sweeping one product never blanks or removes its snapshot - the previous snapshot is kept and
# flagged stale, and other products are refreshed regardless.
class SnapshotRefreshJob {
    *task:Job;

    public function execute() {
        refreshAllSnapshots();
    }
}

# Sweeps every configured product and updates its snapshot, isolating failures per product so one
# failing sweep never prevents the others from refreshing or blanks out previously good data.
function refreshAllSnapshots() {
    foreach string productCode in supportedProductCodes {
        mpe:Entitlement[]|error entitlements = sweepAllEntitlements(productCode);
        if entitlements is error {
            markSnapshotStale(productCode);
            log:printError("entitlement snapshot refresh failed, serving last known snapshot as stale",
                    entitlements, productCode = productCode);
        } else {
            putFreshSnapshot(productCode, entitlements);
        }
    }
}

function initSnapshotRefreshSchedule() returns error? {
    refreshAllSnapshots();
    task:JobId _ = check task:scheduleJobRecurByFrequency(new SnapshotRefreshJob(), refreshIntervalSeconds);
}

final error? snapshotRefreshInit = initSnapshotRefreshSchedule();
