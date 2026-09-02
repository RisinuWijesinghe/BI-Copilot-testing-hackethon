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
|};

# Error response returned to ops when the entitlement sweep could not be completed.
public type ReportingErrorDetail record {
    # Name of the operation that failed.
    string operation;
};
