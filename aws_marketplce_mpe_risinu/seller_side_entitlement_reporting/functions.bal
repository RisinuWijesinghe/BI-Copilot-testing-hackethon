import ballerina/time;
import ballerinax/aws.marketplace.mpe;

# Sweeps every entitlement AWS Marketplace has for the given product, following pagination
# until the full set has been retrieved. Fails entirely if any page fetch fails, rather than
# returning a partial set. Shared by every reporting endpoint so pagination logic lives in one place.
#
# + productCode - the AWS Marketplace product code to sweep entitlements for
# + dimensions - optional set of dimensions to narrow the sweep to; empty means all dimensions
# + return - the complete list of entitlements for the product, or an error naming the failed operation
function sweepAllEntitlements(string productCode, string[] dimensions = []) returns mpe:Entitlement[]|error {
    mpe:Entitlement[] allEntitlements = [];
    string? nextToken = ();
    mpe:EntitlementFilter? filter = dimensions.length() > 0 ? {dimension: dimensions} : ();

    do {
        while true {
            mpe:EntitlementsRequest request = {
                productCode,
                maxResults: entitlementPageSize
            };
            if filter is mpe:EntitlementFilter {
                request.filter = filter;
            }
            if nextToken is string {
                request.nextToken = nextToken;
            }
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

# Validates that every requested dimension is one of the dimensions sold for these products.
#
# + dimensions - caller-supplied dimensions to narrow a report to
# + return - an error naming the first unsupported dimension found, or `()` if all are valid
function validateDimensions(string[] dimensions) returns error? {
    foreach string dimension in dimensions {
        if supportedDimensions.indexOf(dimension) is () {
            return error(string `unsupported dimension: ${dimension}`);
        }
    }
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

# Builds the expiry watchlist for a product from a full entitlement sweep, splitting entitlements
# that have already expired from those still live but due within the requested window, each
# bucket sorted soonest first.
#
# + productCode - the product code the entitlements belong to
# + windowDays - number of days ahead to look for upcoming expiries
# + entitlements - the complete set of entitlements swept for the product
# + return - the expiry watchlist, or an error if an expiry date could not be interpreted
function buildExpiryWatchlist(string productCode, int windowDays, mpe:Entitlement[] entitlements)
        returns ExpiryWatchlist|error {
    time:Utc now = time:utcNow();
    time:Utc windowEnd = time:utcAddSeconds(now, <decimal>windowDays * 86400);

    ExpiringEntitlement[] expiringSoon = [];
    ExpiringEntitlement[] alreadyExpired = [];

    foreach mpe:Entitlement entitlement in entitlements {
        time:Utc? expirationDate = entitlement?.expirationDate;
        if expirationDate is () {
            continue;
        }

        decimal amount = check toEntitledAmount(entitlement?.value);
        ExpiringEntitlement expiringEntitlement = {
            customerIdentifier: entitlement?.customerIdentifier ?: "",
            dimension: entitlement?.dimension ?: "",
            amount,
            expiryDate: time:utcToString(expirationDate)
        };

        if expirationDate < now {
            alreadyExpired.push(expiringEntitlement);
        } else if expirationDate <= windowEnd {
            expiringSoon.push(expiringEntitlement);
        }
    }

    ExpiringEntitlement[] sortedExpiringSoon = from ExpiringEntitlement entitlement in expiringSoon
        order by entitlement.expiryDate ascending
        select entitlement;
    ExpiringEntitlement[] sortedAlreadyExpired = from ExpiringEntitlement entitlement in alreadyExpired
        order by entitlement.expiryDate ascending
        select entitlement;

    return {
        productCode,
        windowDays,
        expiringSoon: sortedExpiringSoon,
        alreadyExpired: sortedAlreadyExpired
    };
}
