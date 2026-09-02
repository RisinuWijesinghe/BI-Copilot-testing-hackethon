import ballerina/test;

@test:Config {}
function testBatchSummaryWithAllValidOrders() returns error? {
    OrderReconciliationEvent event = {
        orderIds: ["ORD-1001", "ORD-1002", "ORD-1003"]
    };

    BatchSummary summary = check buildBatchSummary(event, 5000);

    test:assertEquals(summary.totalMessages, 3, msg = "Total messages should match the number of order ids");
    test:assertEquals(summary.processedCount, 3, msg = "All valid order ids should be processed");
    test:assertEquals(summary.rejectedCount, 0, msg = "No order ids should be rejected");
    test:assertEquals(summary.deadlineTimestamp, 5000, msg = "Deadline timestamp should be passed through as-is");
}

@test:Config {}
function testBatchSummaryWithSomeRejectedOrders() returns error? {
    OrderReconciliationEvent event = {
        orderIds: ["ORD-2001", "", "   ", "ORD-2002"]
    };

    BatchSummary summary = check buildBatchSummary(event, 7500);

    test:assertEquals(summary.totalMessages, 4, msg = "Total messages should match the number of order ids");
    test:assertEquals(summary.processedCount, 2, msg = "Only the well-formed order ids should be processed");
    test:assertEquals(summary.rejectedCount, 2, msg = "Blank order ids should be rejected");
    test:assertEquals(summary.deadlineTimestamp, 7500, msg = "Deadline timestamp should be passed through as-is");
}

@test:Config {}
function testBatchSummaryWithEmptyBatch() returns error? {
    OrderReconciliationEvent event = {
        orderIds: []
    };

    BatchSummary summary = check buildBatchSummary(event, 1000);

    test:assertEquals(summary.totalMessages, 0, msg = "Total messages should be zero for an empty batch");
    test:assertEquals(summary.processedCount, 0, msg = "Processed count should be zero for an empty batch");
    test:assertEquals(summary.rejectedCount, 0, msg = "Rejected count should be zero for an empty batch");
}

@test:Config {}
function testHealthCheckReportsRequestIdAndRemainingTime() {
    HealthStatus healthStatus = buildHealthStatus("test-request-id-123", 12345);

    test:assertEquals(healthStatus.status, "alive", msg = "Health status should report alive");
    test:assertEquals(healthStatus.requestId, "test-request-id-123", msg = "Health status should report the request id");
    test:assertEquals(healthStatus.remainingExecutionTimeMs, 12345,
            msg = "Health status should report the remaining execution time");
}
