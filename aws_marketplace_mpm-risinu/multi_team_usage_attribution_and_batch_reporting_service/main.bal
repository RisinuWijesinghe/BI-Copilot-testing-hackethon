import ballerina/http;
import ballerina/time;
import ballerinax/aws.marketplace.mpm;

service /billing on new http:Listener(8080) {

    # Reports a batch of usage events, aggregated by customer and feature, in a single upstream
    # request, so the day's usage is billed correctly. Every submitted event is matched back to an
    # outcome (accepted, duplicate, not subscribed, or unprocessed) so finance can reconcile the
    # response against what they sent in. Batches larger than AWS Marketplace's per-request limit
    # are rejected up front rather than partially submitted.
    #
    # + request - The batch of usage events to report
    # + return - An outcome for every submitted event, or a 4xx error when the request fails validation
    resource function post usage(UsageBatchReportRequest request) returns UsageBatchReportResponse|http:BadRequest {
        TeamUsageEvent[] usageEvents = request.usageEvents;

        if usageEvents.length() == 0 {
            UsageValidationErrorDetails errorDetails = {
                message: "At least one usage event must be provided.",
                details: "The usageEvents array was empty."
            };
            return <http:BadRequest>{body: errorDetails};
        }

        if usageEvents.length() > MAX_USAGE_EVENTS_PER_BATCH {
            UsageValidationErrorDetails errorDetails = {
                message: "The batch is too large to submit in a single request.",
                details: string `A maximum of ${MAX_USAGE_EVENTS_PER_BATCH} usage events can be reported per request; ${usageEvents.length()} were submitted. Split the batch and resubmit.`
            };
            return <http:BadRequest>{body: errorDetails};
        }

        time:Utc[] eventUtcTimestamps = [];
        foreach TeamUsageEvent usageEvent in usageEvents {
            time:Utc|time:Error eventUtcTimestamp = time:utcFromString(usageEvent.usageTimestamp);
            if eventUtcTimestamp is time:Error {
                UsageValidationErrorDetails errorDetails = {
                    message: "One or more usage events failed validation.",
                    details: string `Invalid usageTimestamp for customer ${usageEvent.customerAwsAccountId}, dimension ${usageEvent.dimension}.`
                };
                return <http:BadRequest>{body: errorDetails};
            }
            eventUtcTimestamps.push(eventUtcTimestamp);
        }

        mpm:UsageRecord[] usageRecords = [];
        foreach TeamUsageEvent usageEvent in usageEvents {
            mpm:UsageRecord|error usageRecord = mapToUsageRecord(usageEvent);
            if usageRecord is error {
                UsageValidationErrorDetails errorDetails = {
                    message: "One or more usage events failed validation.",
                    details: string `Invalid usageTimestamp for customer ${usageEvent.customerAwsAccountId}, dimension ${usageEvent.dimension}.`
                };
                return <http:BadRequest>{body: errorDetails};
            }
            usageRecords.push(usageRecord);
        }

        mpm:BatchMeterUsageResponse|mpm:Error batchResponse = reportUsageBatch(usageRecords);
        if batchResponse is mpm:Error {
            UsageEventOutcome[] failedOutcomes = from TeamUsageEvent usageEvent in usageEvents
                select {
                    customerAwsAccountId: usageEvent.customerAwsAccountId,
                    dimension: usageEvent.dimension,
                    quantity: usageEvent.quantity,
                    usageTimestamp: usageEvent.usageTimestamp,
                    outcomeStatus: "UNPROCESSED",
                    message: "The usage batch could not be submitted to AWS Marketplace; it should be retried."
                };
            return {eventOutcomes: failedOutcomes};
        }

        mpm:UsageRecordResult[] usageRecordResults = batchResponse.results;
        mpm:UsageRecord[] unprocessedRecords = batchResponse.unprocessedRecords;

        UsageEventOutcome[] eventOutcomes = [];
        foreach int index in 0 ..< usageEvents.length() {
            TeamUsageEvent usageEvent = usageEvents[index];
            time:Utc eventUtcTimestamp = eventUtcTimestamps[index];

            mpm:UsageRecord? matchingUnprocessedRecord = ();
            foreach mpm:UsageRecord unprocessedRecord in unprocessedRecords {
                if isMatchingUsageRecord(unprocessedRecord, usageEvent, eventUtcTimestamp) {
                    matchingUnprocessedRecord = unprocessedRecord;
                    break;
                }
            }

            if matchingUnprocessedRecord is mpm:UsageRecord {
                eventOutcomes.push(mapToUnprocessedOutcome(usageEvent));
                continue;
            }

            mpm:UsageRecordResult? matchingResult = ();
            foreach mpm:UsageRecordResult usageRecordResult in usageRecordResults {
                mpm:UsageRecord? resultUsageRecord = usageRecordResult.usageRecord;
                if resultUsageRecord is mpm:UsageRecord && isMatchingUsageRecord(resultUsageRecord, usageEvent, eventUtcTimestamp) {
                    matchingResult = usageRecordResult;
                    break;
                }
            }

            if matchingResult is mpm:UsageRecordResult {
                eventOutcomes.push(mapToProcessedOutcome(matchingResult, usageEvent));
            } else {
                eventOutcomes.push(mapToUnprocessedOutcome(usageEvent));
            }
        }

        return {eventOutcomes};
    }
}

