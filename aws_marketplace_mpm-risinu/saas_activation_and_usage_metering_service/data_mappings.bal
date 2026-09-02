import ballerina/time;
import ballerinax/aws.marketplace.mpm;

# Maps a usage report item accepted from the caller into an AWS Marketplace usage record.
#
# + usageReportItem - The usage item submitted by the billing job
# + resolvedTimestamp - The UTC timestamp to record the usage against
# + return - The AWS Marketplace usage record to submit
function mapToUsageRecord(UsageReportItem usageReportItem, time:Utc resolvedTimestamp) returns mpm:UsageRecord => {
    customerIdentifier: usageReportItem.customerIdentifier,
    dimension: usageReportItem.dimension,
    quantity: usageReportItem.quantity,
    timestamp: resolvedTimestamp
};

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

# Maps a processed AWS Marketplace usage record result to a caller-facing item outcome.
#
# + usageRecordResult - The per-record result returned by AWS Marketplace
# + return - The caller-facing outcome for the corresponding usage item
function mapToProcessedOutcome(mpm:UsageRecordResult usageRecordResult) returns UsageItemOutcome {
    mpm:UsageRecord? usageRecord = usageRecordResult.usageRecord;
    mpm:UsageRecordStatus? usageRecordStatus = usageRecordResult.status;

    string customerIdentifier = "";
    string dimension = "";
    int quantity = 0;
    string usageTimestamp = "";
    if usageRecord is mpm:UsageRecord {
        string? recordCustomerIdentifier = usageRecord.customerIdentifier;
        if recordCustomerIdentifier is string {
            customerIdentifier = recordCustomerIdentifier;
        }
        dimension = usageRecord.dimension;
        int? recordQuantity = usageRecord.quantity;
        if recordQuantity is int {
            quantity = recordQuantity;
        }
        usageTimestamp = time:utcToString(usageRecord.timestamp);
    }

    string outcomeStatus = "UNPROCESSED";
    string message = "AWS Marketplace did not return a status for this usage record.";
    if usageRecordStatus is mpm:UsageRecordStatus {
        outcomeStatus = mapUsageRecordStatusToOutcomeStatus(usageRecordStatus);
        message = buildOutcomeMessage(usageRecordStatus);
    }

    return {
        customerIdentifier,
        dimension,
        quantity,
        usageTimestamp,
        outcomeStatus,
        meteringRecordId: usageRecordResult.meteringRecordId,
        message
    };
}

# Maps an AWS Marketplace usage record that AWS could not process at all into a caller-facing outcome.
#
# + usageRecord - The unprocessed usage record returned by AWS Marketplace
# + return - The caller-facing outcome for the corresponding usage item
function mapToUnprocessedOutcome(mpm:UsageRecord usageRecord) returns UsageItemOutcome {
    string customerIdentifier = "";
    string? recordCustomerIdentifier = usageRecord.customerIdentifier;
    if recordCustomerIdentifier is string {
        customerIdentifier = recordCustomerIdentifier;
    }
    int quantity = 0;
    int? recordQuantity = usageRecord.quantity;
    if recordQuantity is int {
        quantity = recordQuantity;
    }

    return {
        customerIdentifier,
        dimension: usageRecord.dimension,
        quantity,
        usageTimestamp: time:utcToString(usageRecord.timestamp),
        outcomeStatus: "UNPROCESSED",
        message: "AWS Marketplace could not process this usage record; it should be retried."
    };
}
