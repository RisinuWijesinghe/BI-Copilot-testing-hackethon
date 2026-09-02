import ballerina/time;

# Validates a single usage report item before it is sent upstream.
#
# + usageReportItem - The usage item submitted by the billing job
# + return - A rejection reason if the item is invalid, or `()` if it is valid
function validateUsageReportItem(UsageReportItem usageReportItem) returns string? {
    string customerIdentifier = usageReportItem.customerIdentifier.trim();
    if customerIdentifier.length() == 0 {
        return "customerIdentifier is required.";
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
        customerIdentifier: usageReportItem.customerIdentifier,
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
