import ballerina/http;
import ballerinax/aws.marketplace.mpe;

service /entitlements on new http:Listener(servicePort) {

    # Returns a per-dimension breakdown of current subscribers for the given product code,
    # summarizing the complete set of entitlements AWS Marketplace has on record.
    #
    # + productCode - the AWS Marketplace product code to summarize
    # + return - the entitlement summary on success, or an error if the sweep could not be completed
    resource function get [string productCode]/summary() returns EntitlementSummary|http:BadRequest|http:InternalServerError {
        if supportedProductCodes.indexOf(productCode) is () {
            ReportingErrorDetail errorDetail = {operation: "validateProductCode"};
            return <http:BadRequest>{
                body: errorDetail
            };
        }

        mpe:Entitlement[]|error entitlements = sweepAllEntitlements(productCode);
        if entitlements is error {
            ReportingErrorDetail errorDetail = {operation: entitlements.message()};
            return <http:InternalServerError>{
                body: errorDetail
            };
        }

        EntitlementSummary|error summary = buildEntitlementSummary(productCode, entitlements);
        if summary is error {
            ReportingErrorDetail errorDetail = {operation: summary.message()};
            return <http:InternalServerError>{
                body: errorDetail
            };
        }

        return summary;
    }
}
