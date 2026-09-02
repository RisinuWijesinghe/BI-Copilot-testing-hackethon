import ballerina/time;

# A single entitlement a customer holds for our product.
public type EntitlementInfo record {|
    # The dimension the entitlement covers (e.g. "Users", "Bandwidth").
    string dimension;
    # The amount the customer is entitled to for this dimension.
    decimal amount;
    # The RFC 3339 timestamp this entitlement expires at, or `()` if it has no expiry.
    string expiryDate?;
|};

# Error response returned to the caller. Deliberately contains no AWS-originated details -
# no credentials, no raw AWS error message, no AWS request id - only a safe, generic explanation.
public type ErrorDetail record {|
    # Human readable, non-sensitive explanation of what went wrong.
    string message;
    # RFC 3339 timestamp the error occurred at.
    string timestamp;
|};

# Verdict for whether a customer may consume a requested amount of a dimension right now.
public type SeatCheckResult record {|
    # True if the customer holds an unexpired entitlement covering the requested amount.
    boolean allowed;
    # Short, human-readable explanation of the verdict.
    string reason;
|};

# Builds a standard error body with the current time.
#
# + message - the safe, non-sensitive message to surface to the caller
# + return - the error detail record
function newErrorDetail(string message) returns ErrorDetail => {
    message,
    timestamp: time:utcToString(time:utcNow())
};
