import ballerina/log;
import ballerinax/aws.marketplace.mpe;

# Retrieves every entitlement AWS Marketplace has for the given customer against our product,
# following pagination until the full set has been retrieved.
#
# + customerIdentifier - the AWS Marketplace customer identifier to look up
# + return - the complete list of entitlements for the customer, or an error if any page fetch failed
function getCustomerEntitlements(string customerIdentifier) returns mpe:Entitlement[]|error {
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
