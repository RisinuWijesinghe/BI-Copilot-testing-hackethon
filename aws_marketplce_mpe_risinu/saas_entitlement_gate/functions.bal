import ballerina/log;
import ballerina/time;
import ballerinax/aws.marketplace.mpe;

# Retrieves every entitlement AWS Marketplace has for the given customer against our product,
# following pagination until the full set has been retrieved.
#
# + customerIdentifier - the AWS Marketplace customer identifier to look up
# + return - the complete list of entitlements for the customer, or an error if any page fetch failed
function fetchCustomerEntitlementsFromAws(string customerIdentifier) returns mpe:Entitlement[]|error {
    mpe:Entitlement[] allEntitlements = [];
    string? nextToken = ();

    while true {
        mpe:EntitlementsRequest request = {
            productCode,
            filter: {customerIdentifier: [customerIdentifier]}
        };
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

    return allEntitlements;
}

# Retrieves a customer's entitlements against our product, reusing a recently fetched answer from
# the in-memory cache when one is still within the configured TTL, and only calling AWS when the
# cached answer is missing or stale.
#
# + customerIdentifier - the AWS Marketplace customer identifier to look up
# + return - the complete list of entitlements for the customer, or an error if the AWS call failed
function getCustomerEntitlements(string customerIdentifier) returns mpe:Entitlement[]|error {
    mpe:Entitlement[]? cached = getCachedEntitlements(customerIdentifier);
    if cached is mpe:Entitlement[] {
        return cached;
    }

    mpe:Entitlement[] fetched = check fetchCustomerEntitlementsFromAws(customerIdentifier);
    putCachedEntitlements(customerIdentifier, fetched);
    return fetched;
}

# Validates that a caller-supplied customer identifier is present and not blank.
#
# + customerIdentifier - the raw customer identifier from the request
# + return - `()` if valid, or a safe error message describing the validation failure
function validateCustomerIdentifier(string customerIdentifier) returns string? {
    if customerIdentifier.trim().length() == 0 {
        return "customerIdentifier must not be blank";
    }
    return ();
}

# Validates the parts of a seat-check request beyond the customer identifier: the dimension must
# be provided and the requested amount must be a sensible, non-negative number.
#
# + dimension - the dimension the caller wants to consume more of
# + requestedAmount - how much of that dimension the caller is asking for
# + return - `()` if valid, or a safe error message describing the validation failure
function validateSeatCheckRequest(string dimension, decimal requestedAmount) returns string? {
    if dimension.trim().length() == 0 {
        return "dimension must not be blank";
    }
    if requestedAmount < 0d {
        return "amount must not be negative";
    }
    return ();
}

# Decides whether a customer is entitled to consume the requested amount of a dimension. A
# customer counts as entitled only if they hold an unexpired entitlement for that dimension whose
# amount covers the request; an entitlement whose expiry has already passed is treated as no
# entitlement at all, even though AWS still returns it.
#
# + entitlements - the customer's complete set of entitlements against our product
# + dimension - the dimension the caller wants to consume more of
# + requestedAmount - how much of that dimension the caller is asking for
# + return - the seat-check verdict, with a short human-readable reason
function evaluateSeatCheck(mpe:Entitlement[] entitlements, string dimension, decimal requestedAmount)
        returns SeatCheckResult {
    time:Utc now = time:utcNow();
    decimal availableAmount = 0d;

    foreach mpe:Entitlement entitlement in entitlements {
        string entitlementDimension = entitlement?.dimension ?: "";
        if entitlementDimension != dimension {
            continue;
        }

        time:Utc? expirationDate = entitlement?.expirationDate;
        if expirationDate is time:Utc && expirationDate < now {
            continue;
        }

        availableAmount += toAmount(entitlement?.value);
    }

    if availableAmount == 0d {
        return {
            allowed: false,
            reason: string `no active entitlement held for dimension: ${dimension}`
        };
    }

    if availableAmount < requestedAmount {
        return {
            allowed: false,
            reason: string `requested amount exceeds entitled amount for dimension: ${dimension}`
        };
    }

    return {
        allowed: true,
        reason: string `entitlement covers requested amount for dimension: ${dimension}`
    };
}

# Logs an upstream AWS failure with full internal detail for debugging, without ever surfacing
# that detail to the caller.
#
# + operation - name of the operation that failed
# + customerIdentifier - the customer identifier the request was made for
# + cause - the underlying error from the AWS connector call
function logUpstreamFailure(string operation, string customerIdentifier, error cause) {
    log:printError(string `${operation} failed while calling AWS Marketplace Entitlement Service`,
            cause, customerIdentifier = customerIdentifier);
}
