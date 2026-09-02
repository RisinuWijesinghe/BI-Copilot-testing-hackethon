import ballerina/http;
import ballerina/test;
import ballerinax/aws.marketplace.mpm;

final http:Client billingTestClient = check new ("http://localhost:8080/billing");

mpm:BatchMeterUsageResponse|mpm:Error mockBatchMeterUsageResult = error("reportUsageBatch was not stubbed for this test");

@test:Mock {functionName: "reportUsageBatch"}
function mockReportUsageBatch(mpm:UsageRecord[] usageRecords) returns mpm:BatchMeterUsageResponse|mpm:Error {
    return mockBatchMeterUsageResult;
}

@test:Config {}
function testSuccessfulUsageBatchReport() returns error? {
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
            },
            {
                meteringRecordId: "metering-record-2",
                status: mpm:SUCCESS,
                usageRecord: {
                    customerAWSAccountId: "210987654321",
                    dimension: "storage-gb",
                    quantity: 5,
                    timestamp: [1735693200, 0d]
                }
            }
        ],
        unprocessedRecords: []
    };

    UsageBatchReportRequest usageBatchReportRequest = {
        usageEvents: [
            {
                customerAwsAccountId: "123456789012",
                dimension: "api-calls",
                quantity: 42,
                usageTimestamp: "2025-01-01T00:00:00Z"
            },
            {
                customerAwsAccountId: "210987654321",
                dimension: "storage-gb",
                quantity: 5,
                usageTimestamp: "2025-01-01T01:00:00Z"
            }
        ]
    };

    UsageBatchReportResponse response = check billingTestClient->/usage.post(usageBatchReportRequest);

    test:assertEquals(response.eventOutcomes.length(), 2, msg = "Expected exactly one outcome per submitted event");

    UsageEventOutcome firstOutcome = response.eventOutcomes[0];
    test:assertEquals(firstOutcome.customerAwsAccountId, "123456789012", msg = "Customer AWS account ID should be echoed back for the first event");
    test:assertEquals(firstOutcome.dimension, "api-calls", msg = "Dimension should be echoed back for the first event");
    test:assertEquals(firstOutcome.outcomeStatus, "ACCEPTED", msg = "Successfully metered usage should be marked as accepted");

    UsageEventOutcome secondOutcome = response.eventOutcomes[1];
    test:assertEquals(secondOutcome.customerAwsAccountId, "210987654321", msg = "Customer AWS account ID should be echoed back for the second event");
    test:assertEquals(secondOutcome.dimension, "storage-gb", msg = "Dimension should be echoed back for the second event");
    test:assertEquals(secondOutcome.outcomeStatus, "ACCEPTED", msg = "Successfully metered usage should be marked as accepted");
}

@test:Config {}
function testUsageBatchOverSizeLimitIsRejected() returns error? {
    test:prepare(marketplaceMeteringClient).when("batchMeterUsage").thenReturn(error("batchMeterUsage should not be called for an oversized batch"));

    TeamUsageEvent[] usageEvents = [];
    foreach int index in 0 ..< 26 {
        usageEvents.push({
            customerAwsAccountId: "123456789012",
            dimension: "api-calls",
            quantity: 1,
            usageTimestamp: "2025-01-01T00:00:00Z"
        });
    }
    UsageBatchReportRequest usageBatchReportRequest = {usageEvents};

    http:Response response = check billingTestClient->/usage.post(usageBatchReportRequest);
    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST, msg = "A batch larger than the AWS Marketplace limit must be rejected up front");

    UsageValidationErrorDetails errorDetails = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(errorDetails.message, "The batch is too large to submit in a single request.", msg = "The rejection should explain that the batch is too large");
    test:assertTrue(errorDetails.details.includes("25"), msg = "The rejection details should mention the applicable limit");
}

@test:Config {}
function testUsageEventStatusMapping() returns error? {
    mockBatchMeterUsageResult = {
        results: [
            {
                meteringRecordId: "metering-record-1",
                status: mpm:SUCCESS,
                usageRecord: {
                    customerAWSAccountId: "111111111111",
                    dimension: "api-calls",
                    quantity: 10,
                    timestamp: [1735689600, 0d]
                }
            },
            {
                status: mpm:DUPLICATE_RECORD,
                usageRecord: {
                    customerAWSAccountId: "222222222222",
                    dimension: "api-calls",
                    quantity: 20,
                    timestamp: [1735693200, 0d]
                }
            },
            {
                status: mpm:CUSTOMER_NOT_SUBSCRIBED,
                usageRecord: {
                    customerAWSAccountId: "333333333333",
                    dimension: "api-calls",
                    quantity: 30,
                    timestamp: [1735696800, 0d]
                }
            }
        ],
        unprocessedRecords: []
    };

    UsageBatchReportRequest usageBatchReportRequest = {
        usageEvents: [
            {
                customerAwsAccountId: "111111111111",
                dimension: "api-calls",
                quantity: 10,
                usageTimestamp: "2025-01-01T00:00:00Z"
            },
            {
                customerAwsAccountId: "222222222222",
                dimension: "api-calls",
                quantity: 20,
                usageTimestamp: "2025-01-01T01:00:00Z"
            },
            {
                customerAwsAccountId: "333333333333",
                dimension: "api-calls",
                quantity: 30,
                usageTimestamp: "2025-01-01T02:00:00Z"
            }
        ]
    };

    UsageBatchReportResponse response = check billingTestClient->/usage.post(usageBatchReportRequest);

    test:assertEquals(response.eventOutcomes.length(), 3, msg = "Expected exactly one outcome per submitted event");
    test:assertEquals(response.eventOutcomes[0].outcomeStatus, "ACCEPTED", msg = "A successfully metered event should be marked as accepted");
    test:assertEquals(response.eventOutcomes[1].outcomeStatus, "DUPLICATE", msg = "A duplicate record should be marked as duplicate");
    test:assertEquals(response.eventOutcomes[2].outcomeStatus, "NOT_SUBSCRIBED", msg = "An event for an unsubscribed customer should be marked as not subscribed");
}
