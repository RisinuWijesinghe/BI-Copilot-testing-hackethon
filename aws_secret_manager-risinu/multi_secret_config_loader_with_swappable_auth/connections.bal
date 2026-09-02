import ballerinax/aws.auth;
import ballerinax/aws.secretmanager;

final auth:AuthConfig secretManagerAuth = check buildSecretManagerAuthConfig(appEnvironment);

final secretmanager:Client secretManagerClient = check new ({
    region: awsRegion,
    auth: secretManagerAuth
});

// Chooses the AWS auth method based on which environment the app is running
// in. Local development uses a static access-key/secret-key pair; staging and
// production assume an IAM role instead, with no long-lived keys involved.
function buildSecretManagerAuthConfig("local"|"staging"|"production" environment) returns auth:AuthConfig|error {
    if environment == "local" {
        string? accessKeyId = localAwsAccessKeyId;
        string? secretAccessKey = localAwsSecretAccessKey;
        if accessKeyId is () || secretAccessKey is () {
            return error("Local development requires localAwsAccessKeyId and localAwsSecretAccessKey to be set");
        }
        return {
            accessKeyId,
            secretAccessKey
        };
    }

    if environment == "staging" {
        string? roleArn = stagingRoleArn;
        if roleArn is () {
            return error("Staging environment requires stagingRoleArn to be set");
        }
        return {roleArn};
    }

    string? roleArn = productionRoleArn;
    if roleArn is () {
        return error("Production environment requires productionRoleArn to be set");
    }
    return {roleArn};
}
