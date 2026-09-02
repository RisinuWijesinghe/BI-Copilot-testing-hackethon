import ballerinax/aws.marketplace.mpm;

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

