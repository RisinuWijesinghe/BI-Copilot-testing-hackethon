import ballerina/log;
import ballerinax/aws.secretmanager;

# Retrieves the database credentials from the secret store.
#
# On any failure, only a generic, non-sensitive error is returned to the
# caller. The underlying secret contents are never included in a returned
# error or logged; only non-sensitive diagnostic context (secret name, error
# code) is logged.
function fetchDatabaseCredentials() returns DatabaseCredentials|CredentialsNotFound|CredentialsUnavailable {
    secretmanager:SecretValue|secretmanager:Error secretResult = secretManagerClient->getSecretValue(databaseCredentialsSecretId);

    if secretResult is secretmanager:Error {
        if isSecretNotFoundError(secretResult) {
            log:printWarn("Database credentials secret does not exist", secretName = databaseCredentialsSecretId);
            return <CredentialsNotFound>{
                body: {message: "Database credentials are not configured"}
            };
        }

        log:printError("Failed to retrieve database credentials secret", secretName = databaseCredentialsSecretId,
                errorMessage = secretResult.message());
        return <CredentialsUnavailable>{
            body: {message: "Database credentials are currently unavailable"}
        };
    }

    byte[]|string rawValue = secretResult.value;
    string|error jsonText = rawValue is string ? rawValue : string:fromBytes(rawValue);
    if jsonText is error {
        log:printError("Database credentials secret payload is not valid text", secretName = databaseCredentialsSecretId);
        return <CredentialsUnavailable>{
            body: {message: "Database credentials are currently unavailable"}
        };
    }

    json|error secretJson = jsonText.fromJsonString();
    if secretJson is error {
        log:printError("Database credentials secret payload is not valid JSON", secretName = databaseCredentialsSecretId);
        return <CredentialsUnavailable>{
            body: {message: "Database credentials are currently unavailable"}
        };
    }

    DatabaseSecretPayload|error payload = secretJson.cloneWithType(DatabaseSecretPayload);
    if payload is error {
        log:printError("Database credentials secret payload is missing expected fields", secretName = databaseCredentialsSecretId);
        return <CredentialsUnavailable>{
            body: {message: "Database credentials are currently unavailable"}
        };
    }

    return {
        host: payload.host,
        username: payload.username,
        password: payload.password
    };
}

# Determines whether the given error represents the secret not existing in
# the secret store, as opposed to a transient or authentication failure.
function isSecretNotFoundError(secretmanager:Error secretError) returns boolean {
    string errorMessage = secretError.message();
    return errorMessage.includes("ResourceNotFoundException");
}
