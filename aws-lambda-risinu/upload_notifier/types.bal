// Summary returned after processing an S3 upload notification event.
public type UploadSummary record {|
    int totalObjectsProcessed;
    int processedCount;
    int rejectedCount;
|};

// Simple health status payload returned by the Lambda function URL health
// check endpoint so a monitoring tool can poll to confirm the deployment is
// alive. The handlerId field echoes back the environment or instance
// identifier that served the request when the caller supplies one.
public type HealthStatus record {|
    string status;
    string message;
    string handlerId?;
|};

// Clean, user-facing error payload returned instead of an internal failure
// trace when the incoming function URL request looks malformed.
public type ErrorResponse record {|
    string 'error;
    string message;
|};

// HTTP method and request context details of an AWS Lambda function URL
// invocation, following the payload format version 2.0 request context
// shape.
public type FunctionUrlRequestContextHttp record {|
    string method;
    string path;
|};

// Request context wrapper of an AWS Lambda function URL invocation.
public type FunctionUrlRequestContext record {|
    FunctionUrlRequestContextHttp http;
|};

// Represents the AWS Lambda function URL request details received when the
// function is invoked directly over its HTTPS endpoint (payload format
// version 2.0). Only the fields this service relies on are modelled here.
public type FunctionUrlRequest record {|
    string rawPath;
    string rawQueryString;
    FunctionUrlRequestContext requestContext;
    map<string> queryStringParameters?;
|};

// AWS Lambda function URL response envelope (the same proxy-style shape
// used by API Gateway payload format version 2.0 integrations).
public type FunctionUrlResponse record {|
    int statusCode;
    map<string> headers;
    string body;
|};
