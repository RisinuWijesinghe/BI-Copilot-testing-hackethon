import ballerina/time;
import ballerinax/aws.marketplace.mpm;

# Maps a single usage event into an AWS Marketplace usage record.
#
# + teamUsageEvent - The usage event submitted for batch reporting
# + return - The AWS Marketplace usage record to submit, or an error if the timestamp is invalid
function mapToUsageRecord(TeamUsageEvent teamUsageEvent) returns mpm:UsageRecord|error {
    time:Utc usageUtcTimestamp = check time:utcFromString(teamUsageEvent.usageTimestamp);

    return {
        customerAWSAccountId: teamUsageEvent.customerAwsAccountId,
        dimension: teamUsageEvent.dimension,
        quantity: teamUsageEvent.quantity,
        timestamp: usageUtcTimestamp
    };
}

# Maps an AWS Marketplace usage record status to the caller-facing outcome status.
#
# + usageRecordStatus - The status returned by AWS Marketplace for a processed record
# + return - The corresponding caller-facing outcome status
function mapUsageRecordStatusToOutcomeStatus(mpm:UsageRecordStatus usageRecordStatus) returns string {
    match usageRecordStatus {
        mpm:SUCCESS => {
            return "ACCEPTED";
        }
        mpm:DUPLICATE_RECORD => {
            return "DUPLICATE";
        }
        mpm:CUSTOMER_NOT_SUBSCRIBED => {
            return "NOT_SUBSCRIBED";
        }
        _ => {
            return "UNPROCESSED";
        }
    }
}

# Builds the caller-facing message describing a processed usage record outcome.
#
# + usageRecordStatus - The status returned by AWS Marketplace for a processed record
# + return - A human-readable explanation of the outcome
function buildOutcomeMessage(mpm:UsageRecordStatus usageRecordStatus) returns string {
    match usageRecordStatus {
        mpm:SUCCESS => {
            return "Usage was accepted for billing.";
        }
        mpm:DUPLICATE_RECORD => {
            return "This usage record was already reported previously and was not billed again.";
        }
        mpm:CUSTOMER_NOT_SUBSCRIBED => {
            return "The customer is not subscribed to any billable dimension for this product.";
        }
        _ => {
            return "AWS Marketplace returned an unrecognized status for this usage record.";
        }
    }
}

# Maps a processed AWS Marketplace usage record result back to the originally submitted event,
# so finance can reconcile the outcome against their own records.
#
# + usageRecordResult - The per-record result returned by AWS Marketplace
# + teamUsageEvent - The originally submitted event this result corresponds to
# + return - The caller-facing outcome for the corresponding usage event
function mapToProcessedOutcome(mpm:UsageRecordResult usageRecordResult, TeamUsageEvent teamUsageEvent) returns UsageEventOutcome {
    mpm:UsageRecordStatus? usageRecordStatus = usageRecordResult.status;

    string outcomeStatus = "UNPROCESSED";
    string message = "AWS Marketplace did not return a status for this usage event.";
    if usageRecordStatus is mpm:UsageRecordStatus {
        outcomeStatus = mapUsageRecordStatusToOutcomeStatus(usageRecordStatus);
        message = buildOutcomeMessage(usageRecordStatus);
    }

    return {
        customerAwsAccountId: teamUsageEvent.customerAwsAccountId,
        dimension: teamUsageEvent.dimension,
        quantity: teamUsageEvent.quantity,
        usageTimestamp: teamUsageEvent.usageTimestamp,
        outcomeStatus,
        message
    };
}

# Maps a submitted event that AWS Marketplace could not process at all into a caller-facing outcome.
#
# + teamUsageEvent - The originally submitted event that was left unprocessed
# + return - The caller-facing outcome for the corresponding usage event
function mapToUnprocessedOutcome(TeamUsageEvent teamUsageEvent) returns UsageEventOutcome {
    return {
        customerAwsAccountId: teamUsageEvent.customerAwsAccountId,
        dimension: teamUsageEvent.dimension,
        quantity: teamUsageEvent.quantity,
        usageTimestamp: teamUsageEvent.usageTimestamp,
        outcomeStatus: "UNPROCESSED",
        message: "AWS Marketplace could not process this usage event; it should be retried."
    };
}

# Determines whether an AWS Marketplace usage record corresponds to a submitted event, by
# comparing the fields AWS echoes back in its response.
#
# + usageRecord - The usage record returned by AWS Marketplace
# + teamUsageEvent - The originally submitted event to compare against
# + eventUtcTimestamp - The parsed UTC timestamp of the originally submitted event
# + return - True if the usage record corresponds to the submitted event
function isMatchingUsageRecord(mpm:UsageRecord usageRecord, TeamUsageEvent teamUsageEvent, time:Utc eventUtcTimestamp) returns boolean {
    string? recordCustomerAwsAccountId = usageRecord.customerAWSAccountId;
    int? recordQuantity = usageRecord.quantity;
    return recordCustomerAwsAccountId == teamUsageEvent.customerAwsAccountId &&
        usageRecord.dimension == teamUsageEvent.dimension &&
        recordQuantity == teamUsageEvent.quantity &&
        usageRecord.timestamp == eventUtcTimestamp;
}

