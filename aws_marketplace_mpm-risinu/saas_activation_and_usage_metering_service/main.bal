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

service /billing on new http:Listener(8081) {

    # Reports a batch of feature usage chunks for already-activated customers so they can be billed.
    # Every submitted item is rejected up front if it fails validation, otherwise it is reported to
    # AWS Marketplace and its outcome (accepted, duplicate, not subscribed, or unprocessed) is returned.
    #
    # + request - The batch of usage items to report
    # + return - An outcome for every submitted item, or a 4xx error when the request fails validation
    resource function post usage(UsageReportRequest request) returns UsageReportResponse|http:BadRequest {
        UsageReportItem[] usageItems = request.usageItems;

        if usageItems.length() == 0 {
            UsageValidationErrorDetails errorDetails = {
                message: "At least one usage item must be provided.",
                details: "The usageItems array was empty.",
                itemOutcomes: [],
                timestamp: time:utcToString(time:utcNow())
            };
            return <http:BadRequest>{body: errorDetails};
        }

        string?[] validationFailures = from UsageReportItem usageItem in usageItems
            select validateUsageReportItem(usageItem);

        boolean hasInvalidItem = false;
        foreach string? validationFailure in validationFailures {
            if validationFailure is string {
                hasInvalidItem = true;
                break;
            }
        }

        if hasInvalidItem {
            UsageItemOutcome[] rejectedOutcomes = [];
            foreach int index in 0 ..< usageItems.length() {
                string? validationFailure = validationFailures[index];
                if validationFailure is string {
                    rejectedOutcomes.push(buildRejectedOutcome(usageItems[index], validationFailure));
                } else {
                    rejectedOutcomes.push(buildRejectedOutcome(usageItems[index], "Not submitted because other items in the same batch failed validation."));
                }
            }
            UsageValidationErrorDetails errorDetails = {
                message: "One or more usage items failed validation.",
                details: "Fix the rejected items and resubmit the entire batch.",
                itemOutcomes: rejectedOutcomes,
                timestamp: time:utcToString(time:utcNow())
            };
            return <http:BadRequest>{body: errorDetails};
        }

        mpm:UsageRecord[] usageRecords = from UsageReportItem usageItem in usageItems
            select mapToUsageRecord(usageItem, resolveUsageTimestamp(usageItem));

        mpm:BatchMeterUsageResponse|mpm:Error batchResponse = marketplaceMeteringClient->batchMeterUsage(
            productCode = marketplaceProductCode,
            usageRecords = usageRecords
        );

        if batchResponse is mpm:Error {
            UsageItemOutcome[] failedOutcomes = from UsageReportItem usageItem in usageItems
                select {
                    customerIdentifier: usageItem.customerIdentifier,
                    dimension: usageItem.dimension,
                    quantity: usageItem.quantity,
                    usageTimestamp: usageItem.usageTimestamp ?: "",
                    outcomeStatus: "UNPROCESSED",
                    message: "The usage report could not be submitted to AWS Marketplace. It should be retried."
                };
            return {itemOutcomes: failedOutcomes};
        }

        UsageItemOutcome[] itemOutcomes = from mpm:UsageRecordResult usageRecordResult in batchResponse.results
            select mapToProcessedOutcome(usageRecordResult);

        UsageItemOutcome[] unprocessedOutcomes = from mpm:UsageRecord unprocessedRecord in batchResponse.unprocessedRecords
            select mapToUnprocessedOutcome(unprocessedRecord);

        foreach UsageItemOutcome unprocessedOutcome in unprocessedOutcomes {
            itemOutcomes.push(unprocessedOutcome);
        }

        return {itemOutcomes};
    }
}
