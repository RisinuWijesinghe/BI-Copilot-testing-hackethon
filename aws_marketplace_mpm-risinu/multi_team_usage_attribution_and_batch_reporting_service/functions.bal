import ballerinax/aws.marketplace.mpm;

# AWS Marketplace accepts at most this many usage records in a single batchMeterUsage request.
const int MAX_USAGE_EVENTS_PER_BATCH = 25;

# Submits a batch of usage records to AWS Marketplace in a single request.
#
# + usageRecords - The AWS Marketplace usage records to submit
# + return - The batch response from AWS Marketplace, or an error if the call could not be made
function reportUsageBatch(mpm:UsageRecord[] usageRecords) returns mpm:BatchMeterUsageResponse|mpm:Error {
    return marketplaceMeteringClient->batchMeterUsage(
        productCode = marketplaceProductCode,
        usageRecords = usageRecords
    );
}

