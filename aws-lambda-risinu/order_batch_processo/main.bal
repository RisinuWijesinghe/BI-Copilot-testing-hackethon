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

// Triggered whenever new order events land in the SQS queue. Processes every
// message in the batch, validating and parsing each order. Invalid messages
// (bad JSON or missing required fields) are counted as rejected instead of
// failing the whole invocation. If the batch itself cannot be processed at
// all (an outright invocation failure), an error is returned so that AWS
// routes the failed invocation to ON_FAILURE_DESTINATION_ARN; a normal
// return here is routed by AWS to ON_SUCCESS_DESTINATION_ARN.
@lambda:Function
public function processOrderBatch(lambda:Context ctx, lambda:SQSEvent event) returns BatchSummary|error {
    BatchSummary|error summary = buildBatchSummary(ctx, event);
    if summary is error {
        log:printError("order batch invocation failed outright", 'error = summary,
                destinationArn = ON_FAILURE_DESTINATION_ARN);
        return summary;
    }
    log:printInfo("batch processing succeeded", destinationArn = ON_SUCCESS_DESTINATION_ARN, summary = summary);
    return summary;
}

// Builds the batch summary by processing every SQS record in the event.
// Any unexpected, systemic failure while processing the batch (as opposed to
// a single message being rejected) is surfaced as an error here so that the
// invocation fails outright and is routed to the failure destination.
function buildBatchSummary(lambda:Context ctx, lambda:SQSEvent event) returns BatchSummary|error {
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
        rejectedCount: rejectedCount,
        deadlineTimestamp: ctx.getDeadlineMs()
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
