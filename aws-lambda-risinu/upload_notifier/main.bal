import ballerina/log;
import ballerinax/aws.lambda;

// Triggered whenever a file is uploaded to the configured S3 bucket. Logs
// the bucket name, key, and size for every object in the event, and returns
// a JSON summary with the total number of objects processed.
@lambda:Function
public function notifyUpload(lambda:Context ctx, lambda:S3Event event) returns json {
    UploadSummary summary = buildUploadSummary(event);
    log:printInfo("upload notification processed", summary = summary);
    return summary.toJson();
}

// Reachable over an API Gateway HTTP endpoint. Returns a simple status
// payload that a monitoring tool can poll to confirm the deployment is
// healthy. If the incoming request looks malformed, a clean JSON error
// response is returned instead of an internal failure trace.
@lambda:Function
public function healthCheck(lambda:Context ctx, lambda:APIGatewayProxyRequest request) returns json {
    boolean malformedRequest = isMalformedRequest(request);
    if malformedRequest {
        log:printWarn("received malformed health check request", httpMethod = request.httpMethod, path = request.path);
        ProxyResponse errorProxyResponse = buildMalformedRequestResponse();
        return errorProxyResponse.toJson();
    }
    string? handlerId = extractHandlerId(request);
    ProxyResponse healthProxyResponse = buildHealthCheckResponse(handlerId);
    return healthProxyResponse.toJson();
}
