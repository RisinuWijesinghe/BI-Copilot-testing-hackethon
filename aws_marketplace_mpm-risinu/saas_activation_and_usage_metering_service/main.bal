import ballerina/http;
import ballerina/time;
import ballerinax/aws.marketplace.mpm;

service /activation on new http:Listener(8080) {

    # Resolves an AWS Marketplace registration token into the customer's identifying details
    # so the account can be activated.
    #
    # + request - The activation request containing the registration token issued by AWS Marketplace
    # + return - The resolved customer details on success, or a clear 4xx error for an invalid/expired token
    resource function post resolve(ActivationRequest request) returns CustomerActivationDetails|http:BadRequest {
        mpm:ResolveCustomerResponse|mpm:Error response = marketplaceMeteringClient->resolveCustomer(request.registrationToken);

        if response is mpm:Error {
            ActivationErrorDetails errorDetails = {
                message: "The registration token is invalid or has expired.",
                details: "Ask the customer to restart the subscription process from AWS Marketplace to obtain a new registration token.",
                timestamp: time:utcToString(time:utcNow())
            };
            return <http:BadRequest>{body: errorDetails};
        }

        CustomerActivationDetails customerActivationDetails = {
            customerAwsAccountId: response.customerAWSAccountId,
            customerIdentifier: response.customerIdentifier,
            productCode: response.productCode
        };
        return customerActivationDetails;
    }
}
