// Summary returned after processing an S3 upload notification event.
public type UploadSummary record {|
    int totalObjectsProcessed;
|};

// Simple health status payload returned by the API Gateway health check
// endpoint so a monitoring tool can poll to confirm the deployment is alive.
public type HealthStatus record {|
    string status;
    string message;
|};

// Clean, user-facing error payload returned instead of an internal failure
// trace when the incoming API Gateway request looks malformed.
public type ErrorResponse record {|
    string 'error;
    string message;
|};

// AWS API Gateway Lambda proxy integration response envelope.
public type ProxyResponse record {|
    int statusCode;
    map<string> headers;
    string body;
|};
