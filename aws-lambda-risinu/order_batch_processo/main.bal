import ballerina/log;
import ballerinax/aws.lambda;

// Placeholder downstream ARNs for AWS Lambda asynchronous invocation
// destinations. These are wired to the deployed function's event-invoke
// config (e.g. via `aws lambda put-function-event-invoke-config`) so that:
//  - an invocation that fails outright is routed to onFailureDestinationArn
//  - an invocation that completes successfully is routed to onSuccessDestinationArn
// Replace these placeholders with the real downstream ARNs when available.
const string ON_FAILURE_DESTINATION_ARN = "arn:aws:sqs:us-east-1:000000000000:order-batch-failure-destination-placeholder";
const string ON_SUCCESS_DESTINATION_ARN = "arn:aws:sqs:us-east-1:000000000000:order-batch-success-destination-placeholder";

// Triggered periodically by a scheduled job (schedule/event rule) that hands
// over a fixed batch of pending order IDs to reconcile. Invalid order IDs
// (blank or malformed) are counted as rejected instead of failing the whole
// invocation. If the batch itself cannot be processed at all (an outright
// invocation failure), an error is returned so that AWS routes the failed
// invocation to ON_FAILURE_DESTINATION_ARN; a normal return here is routed
// by AWS to ON_SUCCESS_DESTINATION_ARN.
@lambda:Function
public function processOrderBatch(lambda:Context ctx, OrderReconciliationEvent event) returns BatchSummary|error {
    BatchSummary|error summary = buildBatchSummary(event, ctx.getDeadlineMs());
    if summary is error {
        log:printError("order batch invocation failed outright", 'error = summary,
                destinationArn = ON_FAILURE_DESTINATION_ARN);
        return summary;
    }
    log:printInfo("batch processing succeeded", destinationArn = ON_SUCCESS_DESTINATION_ARN, summary = summary);
    return summary;
}

// Builds the batch summary by reconciling every pending order ID in the
// scheduled batch. Any unexpected, systemic failure while processing the
// batch (as opposed to a single order ID being rejected) is surfaced as an
// error here so that the invocation fails outright and is routed to the
// failure destination. Kept independent of lambda:Context so the core logic
// can be unit tested without a live Lambda invocation.
function buildBatchSummary(OrderReconciliationEvent event, int deadlineTimestamp) returns BatchSummary|error {
    string[] orderIds = event.orderIds;
    int processedCount = 0;
    int rejectedCount = 0;

    foreach string orderId in orderIds {
        string|error reconciledOrderId = reconcileOrder(orderId);
        if reconciledOrderId is error {
            rejectedCount += 1;
            log:printWarn("rejected pending order id", orderId = orderId, 'error = reconciledOrderId);
            continue;
        }
        processedCount += 1;
        log:printInfo("reconciled order", orderId = reconciledOrderId);
    }

    BatchSummary summary = {
        totalMessages: orderIds.length(),
        processedCount: processedCount,
        rejectedCount: rejectedCount,
        deadlineTimestamp: deadlineTimestamp
    };
    return summary;
}

// A tiny manually-invocable health-check to confirm the deployment is alive.
// Reports the invocation's request ID and the remaining execution time so the
// runtime environment can be sanity-checked after deploying.
@lambda:Function
public function healthCheck(lambda:Context ctx, json event) returns HealthStatus {
    return buildHealthStatus(ctx.getRequestId(), ctx.getRemainingExecutionTime());
}

// Builds the health-check response from plain values. Kept independent of
// lambda:Context so the core logic can be unit tested without a live Lambda
// invocation.
function buildHealthStatus(string requestId, int remainingExecutionTimeMs) returns HealthStatus {
    HealthStatus healthStatus = {
        status: "alive",
        requestId: requestId,
        remainingExecutionTimeMs: remainingExecutionTimeMs
    };
    return healthStatus;
}
