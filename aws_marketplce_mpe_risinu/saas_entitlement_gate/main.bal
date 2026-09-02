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
}
