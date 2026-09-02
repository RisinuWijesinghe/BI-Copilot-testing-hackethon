import ballerina/http;
import ballerinax/aws.marketplace.mpm;

service /billing on new http:Listener(8080) {

    # Reports a batch of usage events collected from multiple internal teams that share one AWS
    # Marketplace product, in a single upstream request, so the day's usage is billed correctly.
    # Each event is tagged with its originating internal team via a usage allocation so it can be
    # reconciled against internal cost reports later.
    #
    # + request - The batch of usage events to report
    # + return - How many of the submitted events were accepted, or a 4xx error when the request
    # fails validation
    resource function post usage(UsageBatchReportRequest request) returns UsageBatchReportResponse|http:BadRequest {
        TeamUsageEvent[] usageEvents = request.usageEvents;

        if usageEvents.length() == 0 {
            return <http:BadRequest>{body: "At least one usage event must be provided."};
        }

        mpm:UsageRecord[] usageRecords = [];
        foreach TeamUsageEvent usageEvent in usageEvents {
            mpm:UsageRecord|error usageRecord = mapToUsageRecord(usageEvent);
            if usageRecord is error {
                return <http:BadRequest>{
                    body: string `Invalid usageTimestamp for customer ${usageEvent.customerAwsAccountId}, dimension ${usageEvent.dimension}.`
                };
            }
            usageRecords.push(usageRecord);
        }

        mpm:BatchMeterUsageResponse|mpm:Error batchResponse = reportUsageBatch(usageRecords);
        if batchResponse is mpm:Error {
            return <http:BadRequest>{body: "The usage batch could not be submitted to AWS Marketplace."};
        }

        int acceptedCount = 0;
        foreach mpm:UsageRecordResult usageRecordResult in batchResponse.results {
            mpm:UsageRecordStatus? usageRecordStatus = usageRecordResult.status;
            if usageRecordStatus is mpm:UsageRecordStatus && usageRecordStatus == mpm:SUCCESS {
                acceptedCount += 1;
            }
        }

        return {
            acceptedCount,
            totalCount: usageEvents.length()
        };
    }
}

