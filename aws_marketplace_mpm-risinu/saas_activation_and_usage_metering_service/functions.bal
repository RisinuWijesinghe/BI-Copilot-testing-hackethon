import ballerina/lang.regexp;
import ballerina/time;
import ballerinax/aws.marketplace.mpm;

final regexp:RegExp awsAccountIdPattern = check regexp:fromString("^[0-9]{1,255}$");

# Validates a single usage report item before it is sent upstream.
#
# + usageReportItem - The usage item submitted by the billing job
# + return - A rejection reason if the item is invalid, or `()` if it is valid
function validateUsageReportItem(UsageReportItem usageReportItem) returns string? {
    string customerAwsAccountId = usageReportItem.customerAwsAccountId.trim();
    if customerAwsAccountId.length() == 0 {
        return "customerAwsAccountId is required.";
    }
    if !awsAccountIdPattern.isFullMatch(customerAwsAccountId) {
        return "customerAwsAccountId must be a numeric AWS account ID.";
    }
    if usageReportItem.quantity < 0 {
        return "quantity must be zero or a positive integer.";
    }
    string? usageTimestamp = usageReportItem.usageTimestamp;
    if usageTimestamp is string && usageTimestamp.trim().length() > 0 {
        time:Utc|time:Error parsedTimestamp = time:utcFromString(usageTimestamp);
        if parsedTimestamp is time:Error {
            return "usageTimestamp must be a valid RFC 3339 timestamp.";
        }
    }
    return ();
}

# Builds a rejected outcome for a usage item that failed validation.
#
# + usageReportItem - The usage item submitted by the billing job
# + reason - The validation failure reason
# + return - The caller-facing rejected outcome
function buildRejectedOutcome(UsageReportItem usageReportItem, string reason) returns UsageItemOutcome {
    return {
        customerAwsAccountId: usageReportItem.customerAwsAccountId,
        dimension: usageReportItem.dimension,
        quantity: usageReportItem.quantity,
        usageTimestamp: usageReportItem.usageTimestamp ?: "",
        outcomeStatus: "REJECTED",
        message: reason
    };
}

# Resolves the UTC timestamp to record a usage item against, defaulting to now when not supplied.
#
# + usageReportItem - The usage item submitted by the billing job
# + return - The resolved UTC timestamp
function resolveUsageTimestamp(UsageReportItem usageReportItem) returns time:Utc {
    string? usageTimestamp = usageReportItem.usageTimestamp;
    if usageTimestamp is string && usageTimestamp.trim().length() > 0 {
        time:Utc|time:Error parsedTimestamp = time:utcFromString(usageTimestamp);
        if parsedTimestamp is time:Utc {
            return parsedTimestamp;
        }
    }
    return time:utcNow();
}

# Submits a batch of usage records to AWS Marketplace. Isolated behind a plain function so it can be
# swapped out in tests without mocking the connector client object directly.
#
# + usageRecords - The AWS Marketplace usage records to submit
# + return - The batch response from AWS Marketplace, or an error if the call could not be made
function reportUsageBatch(mpm:UsageRecord[] usageRecords) returns mpm:BatchMeterUsageResponse|mpm:Error {
    return marketplaceMeteringClient->batchMeterUsage(
        productCode = marketplaceProductCode,
        usageRecords = usageRecords
    );
}
