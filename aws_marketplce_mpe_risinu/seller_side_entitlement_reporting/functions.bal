import ballerinax/aws.marketplace.mpe;

# Sweeps every entitlement AWS Marketplace has for the given product, following pagination
# until the full set has been retrieved. Fails entirely if any page fetch fails, rather than
# returning a partial set.
#
# + productCode - the AWS Marketplace product code to sweep entitlements for
# + return - the complete list of entitlements for the product, or an error naming the failed operation
function sweepAllEntitlements(string productCode) returns mpe:Entitlement[]|error {
    mpe:Entitlement[] allEntitlements = [];
    string? nextToken = ();

    do {
        while true {
            mpe:EntitlementsRequest request = nextToken is string
                ? {productCode, maxResults: entitlementPageSize, nextToken}
                : {productCode, maxResults: entitlementPageSize};
            mpe:EntitlementsResponse response = check entitlementClient->getEntitlements(request = request);
            allEntitlements.push(...response.entitlements);

            string? responseNextToken = response?.nextToken;
            if responseNextToken is () {
                break;
            }
            nextToken = responseNextToken;
        }
    } on fail error e {
        return error("getEntitlements", cause = e);
    }

    return allEntitlements;
}

# Aggregates a flat list of entitlements into a per-dimension breakdown of customer counts
# and total entitled amounts.
#
# + productCode - the product code the entitlements belong to
# + entitlements - the complete set of entitlements swept for the product
# + return - the aggregated entitlement summary
function buildEntitlementSummary(string productCode, mpe:Entitlement[] entitlements) returns EntitlementSummary|error {
    map<string[]> dimensionToCustomers = {};
    map<decimal> dimensionToTotal = {};

    foreach mpe:Entitlement entitlement in entitlements {
        string dimension = entitlement?.dimension ?: "";
        string customerIdentifier = entitlement?.customerIdentifier ?: "";
        decimal entitledAmount = check toEntitledAmount(entitlement?.value);

        string[]? existingCustomers = dimensionToCustomers[dimension];
        if existingCustomers is string[] {
            if existingCustomers.indexOf(customerIdentifier) is () {
                existingCustomers.push(customerIdentifier);
            }
        } else {
            dimensionToCustomers[dimension] = [customerIdentifier];
        }

        decimal existingTotal = dimensionToTotal[dimension] ?: 0d;
        dimensionToTotal[dimension] = existingTotal + entitledAmount;
    }

    DimensionSummary[] dimensionSummaries = [];
    foreach string dimension in dimensionToCustomers.keys() {
        string[] customers = dimensionToCustomers.get(dimension);
        decimal totalEntitledAmount = dimensionToTotal.get(dimension);
        dimensionSummaries.push({
            dimension,
            customerCount: customers.length(),
            totalEntitledAmount
        });
    }

    return {
        productCode,
        totalEntitlements: entitlements.length(),
        dimensions: dimensionSummaries
    };
}

# Converts an entitlement's value into a decimal amount usable in totals. Non-numeric values
# (e.g. boolean flags) are treated as a unit amount of one.
#
# + entitlementValue - the raw entitlement value returned by AWS Marketplace
# + return - the numeric amount to add to the dimension total
function toEntitledAmount(boolean|float|int|string? entitlementValue) returns decimal|error {
    if entitlementValue is int {
        return <decimal>entitlementValue;
    }
    if entitlementValue is float {
        return <decimal>entitlementValue;
    }
    if entitlementValue is string {
        decimal|error parsed = decimal:fromString(entitlementValue);
        if parsed is decimal {
            return parsed;
        }
        return 1d;
    }
    return 1d;
}
