import ballerina/test;
import ballerinax/aws.lambda;

// Builds a minimal S3 event containing a single record for the given key
// and size, keeping the other required fields populated with simple
// placeholder values.
function buildS3Event(string key, int size) returns lambda:S3Event {
    lambda:S3Identity ownerIdentity = {principalId: "test-owner"};
    lambda:S3Bucket bucket = {
        name: "test-bucket",
        ownerIdentity: ownerIdentity,
        arn: "arn:aws:s3:::test-bucket"
    };
    lambda:S3Object s3Object = {
        key: key,
        size: size,
        eTag: "test-etag",
        sequencer: "test-sequencer"
    };
    lambda:S3Element s3Element = {
        s3SchemaVersion: "1.0",
        configurationId: "test-configuration",
        bucket: bucket,
        'object: s3Object
    };
    lambda:S3Identity userIdentity = {principalId: "test-user"};
    lambda:S3Record s3Record = {
        eventVersion: "2.1",
        eventSource: "aws:s3",
        awsRegion: "us-east-1",
        eventTime: "2026-09-02T18:00:00.000Z",
        eventName: "ObjectCreated:Put",
        userIdentity: userIdentity,
        requestParameters: {},
        responseElements: {},
        s3: s3Element
    };
    lambda:S3Event event = {
        Records: [s3Record]
    };
    return event;
}

@test:Config {}
function testIsOversizedObjectWithNormalSizedObject() {
    lambda:S3Object normalObject = {
        key: "reports/normal.csv",
        size: 1024 * 1024,
        eTag: "test-etag",
        sequencer: "test-sequencer"
    };

    boolean oversized = isOversizedObject(normalObject);

    test:assertFalse(oversized, msg = "An object under 5MB should not be flagged as oversized");
}

@test:Config {}
function testIsOversizedObjectWithOversizedObject() {
    lambda:S3Object oversizedObject = {
        key: "reports/large.csv",
        size: 6 * 1024 * 1024,
        eTag: "test-etag",
        sequencer: "test-sequencer"
    };

    boolean oversized = isOversizedObject(oversizedObject);

    test:assertTrue(oversized, msg = "An object over 5MB should be flagged as oversized");
}

@test:Config {}
function testBuildUploadSummaryWithNormalObjectIsProcessed() {
    lambda:S3Event event = buildS3Event("uploads/normal.csv", 1024 * 1024);

    UploadSummary summary = buildUploadSummary(event);

    test:assertEquals(summary.totalObjectsProcessed, 1, msg = "Total objects should count every record in the event");
    test:assertEquals(summary.processedCount, 1, msg = "A normal sized object should be counted as processed");
    test:assertEquals(summary.rejectedCount, 0, msg = "A normal sized object should not be rejected");
}

@test:Config {}
function testBuildUploadSummaryWithOversizedObjectIsRejected() {
    lambda:S3Event event = buildS3Event("uploads/large.csv", 6 * 1024 * 1024);

    UploadSummary summary = buildUploadSummary(event);

    test:assertEquals(summary.totalObjectsProcessed, 1, msg = "Total objects should count every record in the event");
    test:assertEquals(summary.processedCount, 0, msg = "An oversized object should not be counted as processed");
    test:assertEquals(summary.rejectedCount, 1, msg = "An oversized object should be counted as rejected");
}

// Builds a minimal function URL request with the given HTTP method, path,
// and optional query string parameters.
function buildFunctionUrlRequest(string httpMethod, string path, map<string>? queryStringParameters = ())
        returns FunctionUrlRequest {
    FunctionUrlRequestContextHttp http = {
        method: httpMethod,
        path: path
    };
    FunctionUrlRequestContext requestContext = {
        http: http
    };
    FunctionUrlRequest request = {
        rawPath: path,
        rawQueryString: "",
        requestContext: requestContext,
        queryStringParameters: queryStringParameters
    };
    return request;
}

@test:Config {}
function testIsMalformedRequestWithWellFormedRequest() {
    FunctionUrlRequest request = buildFunctionUrlRequest("GET", "/status");

    boolean malformed = isMalformedRequest(request);

    test:assertFalse(malformed, msg = "A request with a method and path should not be malformed");
}

@test:Config {}
function testIsMalformedRequestWithBlankMethod() {
    FunctionUrlRequest request = buildFunctionUrlRequest(" ", "/status");

    boolean malformed = isMalformedRequest(request);

    test:assertTrue(malformed, msg = "A request with a blank HTTP method should be malformed");
}

@test:Config {}
function testIsMalformedRequestWithBlankPath() {
    FunctionUrlRequest request = buildFunctionUrlRequest("GET", "   ");

    boolean malformed = isMalformedRequest(request);

    test:assertTrue(malformed, msg = "A request with a blank path should be malformed");
}

@test:Config {}
function testExtractHandlerIdWhenSupplied() {
    FunctionUrlRequest request = buildFunctionUrlRequest("GET", "/status", {"handlerId": "prod-instance-2"});

    string? handlerId = extractHandlerId(request);

    test:assertEquals(handlerId, "prod-instance-2", msg = "The supplied handler id should be extracted as-is");
}

@test:Config {}
function testExtractHandlerIdWhenAbsent() {
    FunctionUrlRequest request = buildFunctionUrlRequest("GET", "/status");

    string? handlerId = extractHandlerId(request);

    test:assertEquals(handlerId, (), msg = "No handler id should be extracted when none is supplied");
}

@test:Config {}
function testExtractHandlerIdWhenBlank() {
    FunctionUrlRequest request = buildFunctionUrlRequest("GET", "/status", {"handlerId": "   "});

    string? handlerId = extractHandlerId(request);

    test:assertEquals(handlerId, (), msg = "A blank handler id should be treated as not supplied");
}

@test:Config {}
function testBuildHealthCheckResponseWithHandlerId() returns error? {
    FunctionUrlResponse response = buildHealthCheckResponse("prod-instance-2");

    test:assertEquals(response.statusCode, 200, msg = "A healthy response should report a 200 status code");
    json body = check response.body.fromJsonString();
    HealthStatus healthStatus = check body.cloneWithType(HealthStatus);
    test:assertEquals(healthStatus.status, "UP", msg = "Health status should report UP");
    test:assertEquals(healthStatus.handlerId, "prod-instance-2", msg = "Health status should echo back the handler id");
}

@test:Config {}
function testBuildHealthCheckResponseWithoutHandlerId() returns error? {
    FunctionUrlResponse response = buildHealthCheckResponse(());

    test:assertEquals(response.statusCode, 200, msg = "A healthy response should report a 200 status code");
    json body = check response.body.fromJsonString();
    HealthStatus healthStatus = check body.cloneWithType(HealthStatus);
    test:assertEquals(healthStatus.status, "UP", msg = "Health status should report UP");
    test:assertEquals(healthStatus?.handlerId, (), msg = "Health status should not contain a handler id when none is supplied");
}

@test:Config {}
function testBuildMalformedRequestResponse() returns error? {
    FunctionUrlResponse response = buildMalformedRequestResponse();

    test:assertEquals(response.statusCode, 400, msg = "A malformed request response should report a 400 status code");
    json body = check response.body.fromJsonString();
    ErrorResponse errorResponse = check body.cloneWithType(ErrorResponse);
    test:assertEquals(errorResponse.'error, "BAD_REQUEST", msg = "The error code should indicate a bad request");
}
