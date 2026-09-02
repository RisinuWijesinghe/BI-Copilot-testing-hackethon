import ballerina/log;
import ballerinax/aws.lambda;

// Logs the bucket name, key, and size for a single S3 event record.
function logUploadedObject(lambda:S3Record s3Record) {
    lambda:S3Bucket bucket = s3Record.s3.bucket;
    lambda:S3Object s3Object = s3Record.s3.'object;
    log:printInfo("object uploaded", bucketName = bucket.name, objectKey = s3Object.key, objectSize = s3Object.size);
}

// Builds the upload summary by logging and counting every object present in
// the S3 event. Kept independent of lambda:Context so the core logic can be
// unit tested without a live Lambda invocation.
function buildUploadSummary(lambda:S3Event event) returns UploadSummary {
    lambda:S3Record[] records = event.Records;
    foreach lambda:S3Record s3Record in records {
        logUploadedObject(s3Record);
    }
    UploadSummary summary = {
        totalObjectsProcessed: records.length()
    };
    return summary;
}

// Checks whether an incoming API Gateway proxy request looks well-formed.
// A malformed request is one that is missing the HTTP method or path
// information that API Gateway is expected to always populate.
function isMalformedRequest(lambda:APIGatewayProxyRequest request) returns boolean {
    string httpMethod = request.httpMethod;
    string path = request.path;
    return httpMethod.trim().length() == 0 || path.trim().length() == 0;
}

// Builds the successful health-check proxy response payload.
function buildHealthCheckResponse() returns ProxyResponse {
    HealthStatus healthStatus = {
        status: "UP",
        message: "upload notifier service is healthy"
    };
    ProxyResponse response = {
        statusCode: 200,
        headers: {"Content-Type": "application/json"},
        body: healthStatus.toJsonString()
    };
    return response;
}

// Builds a clean JSON error proxy response for a malformed request instead
// of surfacing anything resembling an internal failure trace.
function buildMalformedRequestResponse() returns ProxyResponse {
    ErrorResponse errorResponse = {
        'error: "BAD_REQUEST",
        message: "the incoming request is malformed"
    };
    ProxyResponse response = {
        statusCode: 400,
        headers: {"Content-Type": "application/json"},
        body: errorResponse.toJsonString()
    };
    return response;
}
