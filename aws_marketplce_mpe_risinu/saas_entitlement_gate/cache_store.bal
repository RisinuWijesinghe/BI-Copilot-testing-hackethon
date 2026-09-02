import ballerina/time;
import ballerinax/aws.marketplace.mpe;

# A cached answer for a single customer's entitlements against our product, together with the
# time it was fetched so callers can tell whether it is still fresh enough to reuse.
type CachedEntitlements record {|
    # The entitlements fetched from AWS Marketplace for this customer, as-is (including any
    # already-expired ones - expiry is judged by callers at read time, not at cache time).
    mpe:Entitlement[] entitlements;
    # The monotonic time the entry was fetched at, used to judge staleness.
    decimal fetchedAtMonotonic;
|};

# Thread-safe in-memory cache holding the most recently fetched entitlements per customer. Reused
# across requests within `cacheTtlSeconds` so a hot endpoint like seat-check does not call AWS on
# every invocation.
isolated map<CachedEntitlements> entitlementsCache = {};

# Reads a customer's cached entitlements if a fetch happened within the configured TTL.
#
# + customerIdentifier - the customer to look up
# + return - the cached entitlements, or `()` if there is no entry or it has gone stale
isolated function getCachedEntitlements(string customerIdentifier) returns mpe:Entitlement[]? {
    lock {
        CachedEntitlements? cached = entitlementsCache[customerIdentifier];
        if cached is () {
            return ();
        }
        decimal age = time:monotonicNow() - cached.fetchedAtMonotonic;
        if age > cacheTtlSeconds {
            return ();
        }
        return cached.entitlements.clone();
    }
}

# Records a freshly fetched set of entitlements for a customer, replacing any existing entry.
#
# + customerIdentifier - the customer the entitlements were fetched for
# + entitlements - the entitlements as returned by AWS Marketplace
isolated function putCachedEntitlements(string customerIdentifier, mpe:Entitlement[] entitlements) {
    CachedEntitlements cached = {
        entitlements: entitlements.clone(),
        fetchedAtMonotonic: time:monotonicNow()
    };
    lock {
        entitlementsCache[customerIdentifier] = cached.clone();
    }
}
