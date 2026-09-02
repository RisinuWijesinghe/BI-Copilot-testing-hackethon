import ballerina/http;
import ballerina/test;
import ballerinax/aws.marketplace.mpm;

final http:Client billingTestClient = check new ("http://localhost:8081/billing");

mpm:BatchMeterUsageResponse|mpm:Error mockBatchMeterUsageResult = error("reportUsageBatch was not stubbed for this test");

@test:Mock {functionName: "reportUsageBatch"}
function mockReportUsageBatch(mpm:UsageRecord[] usageRecords) returns mpm:BatchMeterUsageResponse|mpm:Error {
    return mockBatchMeterUsageResult;
}

@test:Config {}
function testSuccessfulUsageReport() returns error? {
    mockBatchMeterUsageResult = {
        results: [
            {
                meteringRecordId: "metering-record-1",
                status: mpm:SUCCESS,
                usageRecord: {
                    customerAWSAccountId: "123456789012",
                    dimension: "api-calls",
                    quantity: 42,
                    timestamp: [1735689600, 0d]
                }
            }
        ],
        unprocessedRecords: []
    };

    UsageReportRequest usageReportRequest = {
        usageItems: [
            {
                customerAwsAccountId: "123456789012",
                dimension: "api-calls",
                quantity: 42,
                usageTimestamp: "2025-01-01T00:00:00Z"
            }
        ]
    };

    UsageReportResponse response = check billingTestClient->/usage.post(usageReportRequest);

    test:assertEquals(response.itemOutcomes.length(), 1, msg = "Expected exactly one outcome for one submitted item");
    UsageItemOutcome outcome = response.itemOutcomes[0];
    test:assertEquals(outcome.customerAwsAccountId, "123456789012", msg = "Customer AWS account ID should be echoed back");
    test:assertEquals(outcome.outcomeStatus, "ACCEPTED", msg = "Successfully metered usage should be marked as accepted");
    test:assertEquals(outcome.meteringRecordId, "metering-record-1", msg = "Metering record ID should be returned for an accepted item");
}

@test:Config {}
function testUsageReportForCustomerNotSubscribed() returns error? {
    mockBatchMeterUsageResult = {
        results: [
            {
                status: mpm:CUSTOMER_NOT_SUBSCRIBED,
                usageRecord: {
                    customerAWSAccountId: "999999999999",
                    dimension: "api-calls",
                    quantity: 10,
                    timestamp: [1735689600, 0d]
                }
            }
        ],
        unprocessedRecords: []
    };

    UsageReportRequest usageReportRequest = {
        usageItems: [
            {
                customerAwsAccountId: "999999999999",
                dimension: "api-calls",
                quantity: 10,
                usageTimestamp: "2025-01-01T00:00:00Z"
            }
        ]
    };

    UsageReportResponse response = check billingTestClient->/usage.post(usageReportRequest);

    test:assertEquals(response.itemOutcomes.length(), 1, msg = "Expected exactly one outcome for one submitted item");
    UsageItemOutcome outcome = response.itemOutcomes[0];
    test:assertEquals(outcome.customerAwsAccountId, "999999999999", msg = "Customer AWS account ID should be echoed back");
    test:assertEquals(outcome.outcomeStatus, "NOT_SUBSCRIBED", msg = "Customer without a billable subscription should be marked as not subscribed");
}

@test:Config {}
function testUsageReportRejectedBeforeSubmission() returns error? {
    test:prepare(marketplaceMeteringClient).when("batchMeterUsage").thenReturn(error("batchMeterUsage should not be called for an invalid request"));

    UsageReportRequest usageReportRequest = {
        usageItems: [
            {
                customerAwsAccountId: "",
                dimension: "api-calls",
                quantity: -5
            }
        ]
    };

    http:Response response = check billingTestClient->/usage.post(usageReportRequest);
    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST, msg = "Invalid usage items must be rejected with a 4xx response before being submitted upstream");

    UsageValidationErrorDetails errorDetails = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(errorDetails.itemOutcomes.length(), 1, msg = "Every submitted item must be accounted for even when rejected");
    UsageItemOutcome outcome = errorDetails.itemOutcomes[0];
    test:assertEquals(outcome.outcomeStatus, "REJECTED", msg = "The invalid item should be marked as rejected");
    test:assertEquals(outcome.message, "customerAwsAccountId is required.", msg = "The rejection reason should explain the missing customer AWS account ID");
}
