import ballerina/test;
import ballerina/time;
import ballerinax/aws.secretmanager;

final map<string> testSecretIdsByName = {
    apiKey: "arn:aws:secretsmanager:us-east-1:123456789012:secret:api-key",
    signingKey: "arn:aws:secretsmanager:us-east-1:123456789012:secret:signing-key",
    webhookSigningSecret: "arn:aws:secretsmanager:us-east-1:123456789012:secret:webhook-signing-secret"
};

function buildSecretValue(string secretId, string name, string value) returns secretmanager:SecretValue => {
    arn: secretId,
    createdDate: time:utcNow(),
    name,
    value,
    versionId: "00000000000000000000000000000001",
    versionStages: ["AWSCURRENT"]
};

@test:Config {}
function testLoadStartupSecretsSucceedsWhenAllThreeSecretsAreFound() returns error? {
    BatchSecretFetcher fetchAllSecrets = function(string[] secretIds) returns secretmanager:BatchGetSecretValueResponse|secretmanager:Error {
        string apiKeySecretId = testSecretIdsByName.get("apiKey");
        string signingKeySecretId = testSecretIdsByName.get("signingKey");
        string webhookSigningSecretId = testSecretIdsByName.get("webhookSigningSecret");
        secretmanager:SecretValue[] secretValues = [
            buildSecretValue(apiKeySecretId, apiKeySecretId, "api-key-value"),
            buildSecretValue(signingKeySecretId, signingKeySecretId, "signing-key-value"),
            buildSecretValue(webhookSigningSecretId, webhookSigningSecretId, "webhook-signing-secret-value")
        ];
        return {secretValues};
    };

    LoadedSecrets loadedSecrets = check loadStartupSecrets(testSecretIdsByName, fetchAllSecrets);

    map<string> secretValues = loadedSecrets.secretValues;
    test:assertEquals(secretValues.length(), 3, msg = "Expected all three secrets to be loaded");
    test:assertEquals(secretValues.get("apiKey"), "api-key-value", msg = "apiKey value mismatch");
    test:assertEquals(secretValues.get("signingKey"), "signing-key-value", msg = "signingKey value mismatch");
    test:assertEquals(secretValues.get("webhookSigningSecret"), "webhook-signing-secret-value", msg = "webhookSigningSecret value mismatch");
}

@test:Config {}
function testLoadStartupSecretsReportsExactlyWhichSecretIsMissing() {
    BatchSecretFetcher fetchWithSigningKeyMissing = function(string[] secretIds) returns secretmanager:BatchGetSecretValueResponse|secretmanager:Error {
        string apiKeySecretId = testSecretIdsByName.get("apiKey");
        string webhookSigningSecretId = testSecretIdsByName.get("webhookSigningSecret");
        secretmanager:SecretValue[] secretValues = [
            buildSecretValue(apiKeySecretId, apiKeySecretId, "api-key-value"),
            buildSecretValue(webhookSigningSecretId, webhookSigningSecretId, "webhook-signing-secret-value")
        ];
        secretmanager:ApiError[] errors = [
            {
                secretId: testSecretIdsByName.get("signingKey"),
                errorCode: "ResourceNotFoundException",
                message: "Secrets Manager can't find the specified secret"
            }
        ];
        return {secretValues, errors};
    };

    LoadedSecrets|error result = loadStartupSecrets(testSecretIdsByName, fetchWithSigningKeyMissing);

    test:assertTrue(result is error, msg = "Expected startup to fail when a secret is missing");
    error loadError = <error>result;
    string errorMessage = loadError.message();
    test:assertTrue(errorMessage.includes("signingKey"), msg = "Error should name the missing secret by its logical name");
    test:assertTrue(errorMessage.includes("ResourceNotFoundException"), msg = "Error should include the failure code");
}
