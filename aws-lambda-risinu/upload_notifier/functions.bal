import ballerina/log;
import ballerinax/aws.lambda;

// Objects larger than this threshold (in bytes) are flagged as rejected in
// the summary instead of being counted as processed.
const int MAX_ALLOWED_OBJECT_SIZE_BYTES = 5 * 1024 * 1024;

// Logs the bucket name, key, and size for a single S3 event record.
function logUploadedObject(lambda:S3Record s3Record) {
    lambda:S3Bucket bucket = s3Record.s3.bucket;
    lambda:S3Object s3Object = s3Record.s3.'object;
    log:printInfo("object uploaded", bucketName = bucket.name, objectKey = s3Object.key, objectSize = s3Object.size);
}

// Checks whether an uploaded object exceeds the maximum allowed size and
// should therefore be flagged as rejected instead of processed.
function isOversizedObject(lambda:S3Object s3Object) returns boolean {
    return s3Object.size > MAX_ALLOWED_OBJECT_SIZE_BYTES;
}

// Builds the upload summary by logging and counting every object present in
// the S3 event. Objects over the maximum allowed size are flagged as
// rejected rather than processed so oversized uploads are never silently
// treated the same as normal ones. Kept independent of lambda:Context so the
// core logic can be unit tested without a live Lambda invocation.
function buildUploadSummary(lambda:S3Event event) returns UploadSummary {
    lambda:S3Record[] records = event.Records;
    int processedCount = 0;
    int rejectedCount = 0;

    foreach lambda:S3Record s3Record in records {
        logUploadedObject(s3Record);
        lambda:S3Object s3Object = s3Record.s3.'object;
        boolean oversizedObject = isOversizedObject(s3Object);
        if oversizedObject {
            rejectedCount += 1;
            log:printWarn("rejected oversized object", objectKey = s3Object.key, objectSize = s3Object.size,
                    maxAllowedSizeBytes = MAX_ALLOWED_OBJECT_SIZE_BYTES);
            continue;
        }
        processedCount += 1;
    }

    UploadSummary summary = {
        totalObjectsProcessed: records.length(),
        processedCount: processedCount,
        rejectedCount: rejectedCount
    };
    return summary;
}

// Checks whether an incoming Lambda function URL request looks well-formed.
// A malformed request is one that is missing the HTTP method or path
// information that the function URL runtime is expected to always
// populate.
function isMalformedRequest(FunctionUrlRequest request) returns boolean {
    string httpMethod = request.requestContext.http.method;
    string path = request.rawPath;
    return httpMethod.trim().length() == 0 || path.trim().length() == 0;
}

// Extracts the caller-supplied environment or instance identifier from the
// request's query string. Returns () when the caller did not supply one, in
// which case the health check falls back to the plain status payload.
function extractHandlerId(FunctionUrlRequest request) returns string? {
    map<string>? queryStringParameters = request?.queryStringParameters;
    if queryStringParameters is map<string> {
        string? handlerId = queryStringParameters["handlerId"];
        if handlerId is string && handlerId.trim().length() > 0 {
            return handlerId;
        }
    }
    return ();
}

// Builds the successful health-check response payload. When the caller
// supplies an environment or instance identifier, it is echoed back in the
// handlerId field; otherwise the plain status payload is returned.
function buildHealthCheckResponse(string? handlerId) returns FunctionUrlResponse {
    HealthStatus healthStatus = {
        status: "UP",
        message: "upload notifier service is healthy"
    };
    if handlerId is string {
        healthStatus.handlerId = handlerId;
    }
    FunctionUrlResponse response = {
        statusCode: 200,
        headers: {"Content-Type": "application/json"},
        body: healthStatus.toJsonString()
    };
    return response;
}

// Builds a clean JSON error response for a malformed request instead of
// surfacing anything resembling an internal failure trace.
function buildMalformedRequestResponse() returns FunctionUrlResponse {
    ErrorResponse errorResponse = {
        'error: "BAD_REQUEST",
        message: "the incoming request is malformed"
    };
    FunctionUrlResponse response = {
        statusCode: 400,
        headers: {"Content-Type": "application/json"},
        body: errorResponse.toJsonString()
    };
    return response;
}
