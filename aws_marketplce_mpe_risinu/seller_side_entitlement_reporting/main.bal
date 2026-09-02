import ballerina/http;
import ballerinax/aws.marketplace.mpe;

service /entitlements on new http:Listener(servicePort) {

    # Returns a per-dimension breakdown of current subscribers for the given product code,
    # summarizing the complete set of entitlements AWS Marketplace has on record.
    #
    # + productCode - the AWS Marketplace product code to summarize
    # + dimensions - optional set of dimensions to narrow the summary to; omitted means all dimensions
    # + return - the entitlement summary on success, or an error if the request was invalid or the sweep could not be completed
    resource function get [string productCode]/summary(string[] dimensions = [])
            returns EntitlementSummary|http:BadRequest|http:InternalServerError {
        http:BadRequest? validationError = validateReportRequest(productCode, dimensions);
        if validationError is http:BadRequest {
            return validationError;
        }

        mpe:Entitlement[]|error entitlements = sweepAllEntitlements(productCode, dimensions);
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

    # Returns the entitlements coming up for renewal within the given window, soonest first,
    # with already-expired entitlements kept in their own separate bucket.
    #
    # + productCode - the AWS Marketplace product code to check
    # + windowDays - lookahead window, in days; must be a positive number
    # + dimensions - optional set of dimensions to narrow the watchlist to; omitted means all dimensions
    # + return - the expiry watchlist on success, or an error if the request was invalid or the sweep could not be completed
    resource function get [string productCode]/expiring(int windowDays, string[] dimensions = [])
            returns ExpiryWatchlist|http:BadRequest|http:InternalServerError {
        http:BadRequest? validationError = validateReportRequest(productCode, dimensions);
        if validationError is http:BadRequest {
            return validationError;
        }
        if windowDays <= 0 {
            ReportingErrorDetail errorDetail = {
                operation: "validateWindowDays",
                message: "windowDays must be a positive number of days"
            };
            return <http:BadRequest>{
                body: errorDetail
            };
        }

        mpe:Entitlement[]|error entitlements = sweepAllEntitlements(productCode, dimensions);
        if entitlements is error {
            ReportingErrorDetail errorDetail = {operation: entitlements.message()};
            return <http:InternalServerError>{
                body: errorDetail
            };
        }

        ExpiryWatchlist|error watchlist = buildExpiryWatchlist(productCode, windowDays, entitlements);
        if watchlist is error {
            ReportingErrorDetail errorDetail = {operation: watchlist.message()};
            return <http:InternalServerError>{
                body: errorDetail
            };
        }

        return watchlist;
    }
}

# Validates the parts of a report request common to every reporting endpoint: the product code
# must be one we sell, and any requested dimensions must be ones we sell.
#
# + productCode - the AWS Marketplace product code requested
# + dimensions - caller-supplied dimensions to narrow the report to
# + return - a bad request response describing the first validation failure, or `()` if the request is valid
function validateReportRequest(string productCode, string[] dimensions) returns http:BadRequest? {
    if supportedProductCodes.indexOf(productCode) is () {
        ReportingErrorDetail errorDetail = {
            operation: "validateProductCode",
            message: string `unsupported product code: ${productCode}`
        };
        return <http:BadRequest>{
            body: errorDetail
        };
    }

    error? dimensionError = validateDimensions(dimensions);
    if dimensionError is error {
        ReportingErrorDetail errorDetail = {
            operation: "validateDimensions",
            message: dimensionError.message()
        };
        return <http:BadRequest>{
            body: errorDetail
        };
    }

    return ();
}
