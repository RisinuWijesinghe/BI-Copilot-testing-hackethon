import ballerinax/aws.auth;
import ballerinax/aws.dynamodb;

// Runs on EC2 under an instance role, so credentials are resolved from the default AWS
// credential provider chain — no keys are configured or stored with the service.
final dynamodb:Client dynamoDbClient = check new ({
    region: awsRegion,
    auth: auth:DEFAULT_CREDENTIALS
});
