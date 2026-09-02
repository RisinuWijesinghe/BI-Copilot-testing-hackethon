import ballerinax/aws.marketplace.mpe;

# In-memory snapshot of the raw entitlement sweep for a single product, refreshed on a schedule
# in the background. Endpoints derive their responses from this instead of sweeping AWS on demand.
public type ProductSnapshot record {|
    # The complete set of entitlements retrieved for the product as of `lastRefreshed`.
    mpe:Entitlement[] entitlements;
    # RFC 3339 timestamp of the last successful or failed refresh attempt.
    string lastRefreshed;
    # True when the most recent scheduled refresh failed and this snapshot is carried over from
    # an earlier successful refresh rather than reflecting the latest data.
    boolean stale;
|};

# Aggregated entitlement statistics for a single dimension of a product.
public type DimensionSummary record {|
    # The dimension name (e.g. "Users", "Bandwidth").
    string dimension;
    # Number of distinct customers holding an entitlement for this dimension.
    int customerCount;
    # Total entitled amount summed across all customers for this dimension.
    decimal totalEntitledAmount;
|};

# Full entitlement summary for a product, broken down by dimension.
public type EntitlementSummary record {|
    # The AWS Marketplace product code the summary was computed for.
    string productCode;
    # Total number of entitlement records swept for this product.
    int totalEntitlements;
    # Per-dimension breakdown of customer counts and entitled amounts.
    DimensionSummary[] dimensions;
    # RFC 3339 timestamp of the background refresh this summary was computed from.
    string lastRefreshed;
    # True when the underlying snapshot is carried over from a failed refresh, i.e. this summary
    # may not reflect the latest entitlements.
    boolean stale;
|};

# Error response returned to ops when the entitlement sweep could not be completed or the request was invalid.
public type ReportingErrorDetail record {
    # Name of the operation that failed.
    string operation;
    # Human readable explanation of the failure.
    string message?;
};

# A single entitlement coming up for renewal (or already expired), as shown on the watchlist.
public type ExpiringEntitlement record {|
    # Identifier of the customer holding the entitlement.
    string customerIdentifier;
    # The dimension the entitlement applies to.
    string dimension;
    # The entitled amount.
    decimal amount;
    # The RFC 3339 timestamp the entitlement expires at.
    string expiryDate;
|};

# Expiry watchlist for a product: entitlements still live but expiring within the requested
# window, and entitlements that have already expired, kept in their own separate bucket.
public type ExpiryWatchlist record {|
    # The AWS Marketplace product code the watchlist was computed for.
    string productCode;
    # The size of the lookahead window, in days, that was requested.
    int windowDays;
    # Entitlements expiring within the window, soonest first.
    ExpiringEntitlement[] expiringSoon;
    # Entitlements that have already expired, soonest-expired first, kept separate from `expiringSoon`.
    ExpiringEntitlement[] alreadyExpired;
    # RFC 3339 timestamp of the background refresh this watchlist was computed from.
    string lastRefreshed;
    # True when the underlying snapshot is carried over from a failed refresh, i.e. this watchlist
    # may not reflect the latest entitlements.
    boolean stale;
|};
