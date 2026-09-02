import ballerina/time;
import ballerinax/aws.marketplace.mpe;

# Thread-safe in-memory store holding the latest entitlement snapshot per product. Written to by
# the scheduled refresh job and read by the HTTP resources, so all access goes through a lock.
isolated map<ProductSnapshot> productSnapshots = {};

# Replaces the snapshot for a product after a successful refresh.
#
# + productCode - the product the snapshot belongs to
# + entitlements - the freshly swept entitlements
isolated function putFreshSnapshot(string productCode, mpe:Entitlement[] entitlements) {
    ProductSnapshot snapshot = {
        entitlements: entitlements.clone(),
        lastRefreshed: time:utcToString(time:utcNow()),
        stale: false
    };
    lock {
        productSnapshots[productCode] = snapshot.clone();
    }
}

# Marks the existing snapshot for a product as stale after a failed refresh, keeping its
# entitlements untouched. If no snapshot exists yet (e.g. the very first refresh failed), an
# empty stale snapshot is recorded so the product is never silently missing.
#
# + productCode - the product whose refresh failed
isolated function markSnapshotStale(string productCode) {
    lock {
        ProductSnapshot? existing = productSnapshots[productCode];
        if existing is ProductSnapshot {
            productSnapshots[productCode] = {
                entitlements: existing.entitlements,
                lastRefreshed: existing.lastRefreshed,
                stale: true
            };
        } else {
            productSnapshots[productCode] = {
                entitlements: [],
                lastRefreshed: time:utcToString(time:utcNow()),
                stale: true
            };
        }
    }
}

# Reads the current snapshot for a product.
#
# + productCode - the product to look up
# + return - the current snapshot, or `()` if no refresh has ever run for this product
isolated function getSnapshot(string productCode) returns ProductSnapshot? {
    lock {
        ProductSnapshot? snapshot = productSnapshots[productCode];
        return snapshot is ProductSnapshot ? snapshot.clone() : ();
    }
}
