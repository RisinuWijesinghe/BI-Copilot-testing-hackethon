import ballerina/http;
import ballerinax/aws.marketplace.mpe;

service /entitlements on new http:Listener(servicePort) {

    # Returns a per-dimension breakdown of current subscribers for the given product code, computed
    # instantly from the latest background-refreshed snapshot instead of sweeping AWS on demand.
    #
    # + productCode - the AWS Marketplace product code to summarize
    # + dimensions - optional set of dimensions to narrow the summary to; omitted means all dimensions
    # + return - the entitlement summary on success, or an error if the request was invalid or no snapshot is available yet
    resource function get [string productCode]/summary(string[] dimensions = [])
            returns EntitlementSummary|http:BadRequest|http:InternalServerError {
        http:BadRequest? validationError = validateReportRequest(productCode, dimensions);
        if validationError is http:BadRequest {
            return validationError;
        }

        ProductSnapshot|http:InternalServerError snapshot = loadSnapshotOrError(productCode);
        if snapshot is http:InternalServerError {
            return snapshot;
        }

        mpe:Entitlement[] filteredEntitlements = filterByDimensions(snapshot.entitlements, dimensions);
        EntitlementSummary|error summary = buildEntitlementSummary(productCode, filteredEntitlements,
                snapshot.lastRefreshed, snapshot.stale);
        if summary is error {
            ReportingErrorDetail errorDetail = {operation: summary.message()};
            return <http:InternalServerError>{
                body: errorDetail
            };
        }

        return summary;
    }

    # Returns the entitlements coming up for renewal within the given window, soonest first, with
    # already-expired entitlements kept in their own separate bucket. Computed instantly from the
    # latest background-refreshed snapshot instead of sweeping AWS on demand.
    #
    # + productCode - the AWS Marketplace product code to check
    # + windowDays - lookahead window, in days; must be a positive number
    # + dimensions - optional set of dimensions to narrow the watchlist to; omitted means all dimensions
    # + return - the expiry watchlist on success, or an error if the request was invalid or no snapshot is available yet
    resource function get [string productCode]/expiring(int windowDays, string[] dimensions = [])
            returns ExpiryWatchlist|http:BadRequest|http:InternalServerError {
        ExpiryWatchlist|http:BadRequest|http:InternalServerError result =
                computeWatchlist(productCode, windowDays, dimensions);
        return result;
    }

    # Returns the entitlements coming up for renewal within the given window as a CSV document,
    # ready to drop into a spreadsheet.
    #
    # + productCode - the AWS Marketplace product code to check
    # + windowDays - lookahead window, in days; must be a positive number
    # + dimensions - optional set of dimensions to narrow the watchlist to; omitted means all dimensions
    # + return - the expiry watchlist rendered as CSV, or an error if the request was invalid or no snapshot is available yet
    resource function get [string productCode]/expiring\.csv(int windowDays, string[] dimensions = [])
            returns http:Response|http:BadRequest|http:InternalServerError {
        ExpiryWatchlist|http:BadRequest|http:InternalServerError result =
                computeWatchlist(productCode, windowDays, dimensions);
        if result is http:BadRequest|http:InternalServerError {
            return result;
        }

        string csv = watchlistToCsv(result);
        http:Response response = new;
        response.setTextPayload(csv, contentType = "text/csv");
        response.setHeader("Content-Disposition", string `attachment; filename="${productCode}-expiring.csv"`);
        return response;
    }
}

# Computes the expiry watchlist for a product from its current snapshot, applying validation and
# dimension narrowing shared with the JSON and CSV endpoints.
#
# + productCode - the AWS Marketplace product code to check
# + windowDays - lookahead window, in days; must be a positive number
# + dimensions - optional set of dimensions to narrow the watchlist to; omitted means all dimensions
# + return - the expiry watchlist on success, or an error response describing why it could not be computed
function computeWatchlist(string productCode, int windowDays, string[] dimensions)
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

    ProductSnapshot|http:InternalServerError snapshot = loadSnapshotOrError(productCode);
    if snapshot is http:InternalServerError {
        return snapshot;
    }

    mpe:Entitlement[] filteredEntitlements = filterByDimensions(snapshot.entitlements, dimensions);
    ExpiryWatchlist|error watchlist = buildExpiryWatchlist(productCode, windowDays, filteredEntitlements,
            snapshot.lastRefreshed, snapshot.stale);
    if watchlist is error {
        ReportingErrorDetail errorDetail = {operation: watchlist.message()};
        return <http:InternalServerError>{
            body: errorDetail
        };
    }

    return watchlist;
}

# Loads the current snapshot for a product, failing clearly if the background job has not
# produced one yet (e.g. the service just started and the very first refresh is still running).
#
# + productCode - the product to look up
# + return - the current snapshot, or an internal server error if none is available yet
function loadSnapshotOrError(string productCode) returns ProductSnapshot|http:InternalServerError {
    ProductSnapshot? snapshot = getSnapshot(productCode);
    if snapshot is () {
        ReportingErrorDetail errorDetail = {
            operation: "loadSnapshot",
            message: "no snapshot available yet for this product"
        };
        return <http:InternalServerError>{
            body: errorDetail
        };
    }
    return snapshot;
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
