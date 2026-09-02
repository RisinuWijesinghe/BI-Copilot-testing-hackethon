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
            mpe:EntitlementsResponse response = check fetchEntitlementsPage(request);
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

# Fetches a single page of entitlements from AWS Marketplace. Kept as a thin, separately-named
# wrapper around the connector call so tests can substitute it and drive pagination without a
# real AWS account.
#
# + request - the entitlements request for this page
# + return - the page response, or an error if the call failed
function fetchEntitlementsPage(mpe:EntitlementsRequest request) returns mpe:EntitlementsResponse|error {
    return entitlementClient->getEntitlements(request = request);
}

# Narrows a full entitlement snapshot down to the requested dimensions. An empty filter list
# means no narrowing is applied.
#
# + entitlements - the complete set of entitlements from a product's snapshot
# + dimensions - the dimensions to keep; empty means keep everything
# + return - the entitlements belonging to one of the requested dimensions
function filterByDimensions(mpe:Entitlement[] entitlements, string[] dimensions) returns mpe:Entitlement[] {
    if dimensions.length() == 0 {
        return entitlements;
    }
    return from mpe:Entitlement entitlement in entitlements
        where dimensions.indexOf(entitlement?.dimension ?: "") is int
        select entitlement;
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
# + lastRefreshed - timestamp of the background refresh the entitlements were taken from
# + stale - whether the underlying snapshot is carried over from a failed refresh
# + return - the aggregated entitlement summary
function buildEntitlementSummary(string productCode, mpe:Entitlement[] entitlements, string lastRefreshed,
        boolean stale) returns EntitlementSummary|error {
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
        dimensions: dimensionSummaries,
        lastRefreshed,
        stale
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
# + lastRefreshed - timestamp of the background refresh the entitlements were taken from
# + stale - whether the underlying snapshot is carried over from a failed refresh
# + return - the expiry watchlist, or an error if an expiry date could not be interpreted
function buildExpiryWatchlist(string productCode, int windowDays, mpe:Entitlement[] entitlements,
        string lastRefreshed, boolean stale) returns ExpiryWatchlist|error {
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
        alreadyExpired: sortedAlreadyExpired,
        lastRefreshed,
        stale
    };
}

# Renders an expiry watchlist as CSV so ops can drop it straight into a spreadsheet. Already-expired
# entitlements are listed after the still-live ones, with a status column distinguishing the two.
#
# + watchlist - the expiry watchlist to render
# + return - the watchlist as a CSV document, including a header row
function watchlistToCsv(ExpiryWatchlist watchlist) returns string {
    string[] lines = ["customerIdentifier,dimension,amount,expiryDate,status"];
    foreach ExpiringEntitlement entitlement in watchlist.expiringSoon {
        lines.push(toCsvRow(entitlement, "EXPIRING_SOON"));
    }
    foreach ExpiringEntitlement entitlement in watchlist.alreadyExpired {
        lines.push(toCsvRow(entitlement, "ALREADY_EXPIRED"));
    }
    return string:'join("\n", ...lines) + "\n";
}

# Renders a single watchlist entry as one CSV row.
#
# + entitlement - the entry to render
# + status - the bucket the entry belongs to
# + return - the CSV row, without a trailing newline
function toCsvRow(ExpiringEntitlement entitlement, string status) returns string {
    return string `${entitlement.customerIdentifier},${entitlement.dimension},${entitlement.amount},${entitlement.expiryDate},${status}`;
}
