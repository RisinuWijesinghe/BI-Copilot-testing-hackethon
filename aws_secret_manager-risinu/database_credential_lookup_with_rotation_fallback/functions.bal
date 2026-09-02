import ballerina/log;
import ballerinax/aws.secretmanager;

# Categorizes a secret-fetch failure so callers can build the right error
# response.
type SecretFetchFailure SECRET_NOT_FOUND|STALE_CREDENTIALS|OTHER_FAILURE;

# The named secret itself does not exist in the secret store.
const SECRET_NOT_FOUND = "SECRET_NOT_FOUND";
# The secret exists, but the current version/stage of it is not available -
# this means the credentials are out of date and must not be silently
# masked by falling back to an older version.
const STALE_CREDENTIALS = "STALE_CREDENTIALS";
# Any other failure, e.g. an authentication problem with the secret store
# itself, which must fail immediately rather than being retried.
const OTHER_FAILURE = "OTHER_FAILURE";

# Retrieves the database credentials from the secret store.
#
# Only ever fetches the current secret version. If the current version is
# not available for any reason (e.g. it has not propagated yet right after a
# rotation), this fails loudly rather than silently falling back to an older
# version, since serving stale credentials would mask a rotation problem
# instead of surfacing it.
#
# On any failure, only a generic, non-sensitive error is returned to the
# caller. The underlying secret contents are never included in a returned
# error or logged; only non-sensitive diagnostic context (secret name, error
# code) is logged.
function fetchDatabaseCredentials() returns DatabaseCredentials|CredentialsNotFound|CredentialsOutOfDate|CredentialsUnavailable {
    secretmanager:SecretValue|secretmanager:Error currentVersionResult = secretManagerClient->getSecretValue(databaseCredentialsSecretId);

    if currentVersionResult is secretmanager:Error {
        SecretFetchFailure failureKind = classifySecretFetchError(currentVersionResult);
        return handleSecretFetchFailure(failureKind, currentVersionResult);
    }

    return toDatabaseCredentials(currentVersionResult);
}

# Builds the appropriate error response for a classified secret-fetch
# failure, logging only non-sensitive diagnostic context.
function handleSecretFetchFailure(SecretFetchFailure failureKind, secretmanager:Error secretError) returns CredentialsNotFound|CredentialsOutOfDate|CredentialsUnavailable {
    if failureKind == SECRET_NOT_FOUND {
        log:printWarn("Database credentials secret does not exist", secretName = databaseCredentialsSecretId);
        return <CredentialsNotFound>{
            body: {message: "Database credentials are not configured"}
        };
    }

    if failureKind == STALE_CREDENTIALS {
        log:printError("Current version of database credentials secret is not available - credentials are out of date",
                secretName = databaseCredentialsSecretId, errorMessage = secretError.message());
        return <CredentialsOutOfDate>{
            body: {message: "Database credentials are out of date: the current secret version is not available"}
        };
    }

    log:printError("Failed to retrieve database credentials secret", secretName = databaseCredentialsSecretId,
            errorMessage = secretError.message());
    return <CredentialsUnavailable>{
        body: {message: "Database credentials are currently unavailable"}
    };
}

# Determines whether the given error represents the secret not existing, the
# current version/stage of it not being available, or some other failure
# (e.g. authentication) with the secret store.
function classifySecretFetchError(secretmanager:Error secretError) returns SecretFetchFailure {
    string errorMessage = secretError.message();
    if errorMessage.includes("ResourceNotFoundException") {
        return SECRET_NOT_FOUND;
    }
    if errorMessage.includes("InvalidRequestException") && errorMessage.includes("version") {
        return STALE_CREDENTIALS;
    }
    return OTHER_FAILURE;
}

# Parses a secret's JSON blob into the database credentials returned by the
# service. Any parsing failure is reported without exposing the secret
# contents.
function toDatabaseCredentials(secretmanager:SecretValue secretValue) returns DatabaseCredentials|CredentialsUnavailable {
    byte[]|string rawValue = secretValue.value;
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
