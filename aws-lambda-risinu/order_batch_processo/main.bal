import ballerina/log;
import ballerinax/aws.lambda;

// Triggered whenever new order events land in the SQS queue. Processes every
// message in the batch, validating and parsing each order. Invalid messages
// (bad JSON or missing required fields) are counted as rejected instead of
// failing the whole invocation.
@lambda:Function
public function processOrderBatch(lambda:Context ctx, lambda:SQSEvent event) returns BatchSummary {
    lambda:SQSRecord[] records = event.Records;
    int processedCount = 0;
    int rejectedCount = 0;

    foreach lambda:SQSRecord sqsRecord in records {
        OrderRecord|error orderRecord = parseOrder(sqsRecord.body);
        if orderRecord is error {
            rejectedCount += 1;
            log:printWarn("rejected order message", messageId = sqsRecord.messageId, 'error = orderRecord);
            continue;
        }
        processedCount += 1;
        log:printInfo("processed order", orderId = orderRecord.orderId, customerId = orderRecord.customerId);
    }

    BatchSummary summary = {
        totalMessages: records.length(),
        processedCount: processedCount,
        rejectedCount: rejectedCount
    };
    return summary;
}

// A tiny manually-invocable health-check to confirm the deployment is alive.
// Reports the invocation's request ID and the remaining execution time so the
// runtime environment can be sanity-checked after deploying.
@lambda:Function
public function healthCheck(lambda:Context ctx, json event) returns HealthStatus {
    HealthStatus healthStatus = {
        status: "alive",
        requestId: ctx.getRequestId(),
        remainingExecutionTimeMs: ctx.getRemainingExecutionTime()
    };
    return healthStatus;
}
