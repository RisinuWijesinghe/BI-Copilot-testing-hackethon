import ballerina/http;
import ballerinax/aws.marketplace.mpe;

service /entitlements on new http:Listener(servicePort) {

    # Returns the entitlements the given AWS Marketplace customer holds for our product: for each
    # one, the dimension it covers, how much they're entitled to, and when it expires.
    #
    # + customerIdentifier - the AWS Marketplace customer identifier to look up
    # + return - the customer's entitlements on success; a bad request if the identifier is blank;
    #            not found if the customer has no entitlements; or a bad gateway if the AWS call failed
    resource function get customers/[string customerIdentifier]/entitlements()
            returns EntitlementInfo[]|http:BadRequest|http:NotFound|http:BadGateway {
        string? validationError = validateCustomerIdentifier(customerIdentifier);
        if validationError is string {
            return <http:BadRequest>{
                body: newErrorDetail(validationError)
            };
        }

        mpe:Entitlement[]|error entitlements = getCustomerEntitlements(customerIdentifier);
        if entitlements is error {
            logUpstreamFailure("getCustomerEntitlements", customerIdentifier, entitlements);
            return <http:BadGateway>{
                body: newErrorDetail("failed to retrieve entitlements from AWS Marketplace")
            };
        }

        if entitlements.length() == 0 {
            return <http:NotFound>{
                body: newErrorDetail("no entitlements found for this customer")
            };
        }

        return toEntitlementInfoList(entitlements);
    }

    # Checks whether a customer may consume a requested amount of a dimension right now, e.g.
    # before letting them add more users or storage. A denial is a normal, successful outcome -
    # only a bad request (blank identifier/dimension, negative amount) or a failure to reach AWS
    # produce an error response, and neither ever surfaces AWS-originated details.
    #
    # + customerIdentifier - the AWS Marketplace customer identifier to check
    # + dimension - the dimension the caller wants to consume more of (e.g. "Users", "Storage")
    # + amount - how much of that dimension the caller is asking for
    # + return - the allow-or-deny verdict on success; a bad request if the input was invalid;
    #            or a bad gateway if the AWS call failed
    resource function get customers/[string customerIdentifier]/seatCheck(string dimension, decimal amount)
            returns SeatCheckResult|http:BadRequest|http:BadGateway {
        string? identifierError = validateCustomerIdentifier(customerIdentifier);
        if identifierError is string {
            return <http:BadRequest>{
                body: newErrorDetail(identifierError)
            };
        }

        string? requestError = validateSeatCheckRequest(dimension, amount);
        if requestError is string {
            return <http:BadRequest>{
                body: newErrorDetail(requestError)
            };
        }

        mpe:Entitlement[]|error entitlements = getCustomerEntitlements(customerIdentifier);
        if entitlements is error {
            logUpstreamFailure("checkSeatEntitlement", customerIdentifier, entitlements);
            return <http:BadGateway>{
                body: newErrorDetail("failed to retrieve entitlements from AWS Marketplace")
            };
        }

        return evaluateSeatCheck(entitlements, dimension, amount);
    }
}
