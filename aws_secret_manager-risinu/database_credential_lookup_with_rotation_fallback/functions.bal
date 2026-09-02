import ballerina/log;
import ballerinax/aws.secretmanager;

# The version stage identifying the secret version that was active
# immediately before the most recent rotation.
const string PREVIOUS_VERSION_STAGE = "AWSPREVIOUS";

# Categorizes a secret-fetch failure so callers can decide whether the
# rotation fallback applies.
type SecretFetchFailure SECRET_NOT_FOUND|VERSION_NOT_FOUND|OTHER_FAILURE;

# The named secret itself does not exist in the secret store.
const SECRET_NOT_FOUND = "SECRET_NOT_FOUND";
# The secret exists, but the requested version/stage of it does not - the
# only failure kind that should trigger a fallback to the previous version.
const VERSION_NOT_FOUND = "VERSION_NOT_FOUND";
# Any other failure, e.g. an authentication problem with the secret store
# itself, which must fail immediately rather than being retried.
const OTHER_FAILURE = "OTHER_FAILURE";

# Retrieves the database credentials from the secret store.
#
# Tries the current secret version first. If that specific version cannot be
# found (the short window right after rotation where the new version has not
# propagated to every consumer yet), automatically falls back to the previous
# version. Any other kind of failure - the secret itself not existing, or an
# authentication problem with the secret store - fails immediately and is not
# retried.
#
# On any failure, only a generic, non-sensitive error is returned to the
# caller. The underlying secret contents are never included in a returned
# error or logged; only non-sensitive diagnostic context (secret name, error
# code) is logged.
function fetchDatabaseCredentials() returns DatabaseCredentials|CredentialsNotFound|CredentialsUnavailable {
    secretmanager:SecretValue|secretmanager:Error currentVersionResult = secretManagerClient->getSecretValue(databaseCredentialsSecretId);

    if currentVersionResult is secretmanager:Error {
        SecretFetchFailure failureKind = classifySecretFetchError(currentVersionResult);

        if failureKind == VERSION_NOT_FOUND {
            log:printWarn("Current version of database credentials secret not yet propagated, falling back to previous version",
                    secretName = databaseCredentialsSecretId);
            return fetchPreviousVersionCredentials();
        }

        return handleSecretFetchFailure(failureKind, currentVersionResult);
    }

    return toDatabaseCredentials(currentVersionResult);
}

# Retrieves the previous version of the database credentials secret, used as
# a fallback right after rotation while the current version is still
# propagating. Any failure here (including the previous version itself being
# unavailable) is reported as a plain failure, with no further fallback.
function fetchPreviousVersionCredentials() returns DatabaseCredentials|CredentialsNotFound|CredentialsUnavailable {
    secretmanager:SecretValue|secretmanager:Error previousVersionResult =
        secretManagerClient->getSecretValue(databaseCredentialsSecretId, versionStage = PREVIOUS_VERSION_STAGE);

    if previousVersionResult is secretmanager:Error {
        SecretFetchFailure failureKind = classifySecretFetchError(previousVersionResult);
        return handleSecretFetchFailure(failureKind, previousVersionResult);
    }

    return toDatabaseCredentials(previousVersionResult);
}

# Builds the appropriate error response for a classified secret-fetch
# failure, logging only non-sensitive diagnostic context.
function handleSecretFetchFailure(SecretFetchFailure failureKind, secretmanager:Error secretError) returns CredentialsNotFound|CredentialsUnavailable {
    if failureKind == SECRET_NOT_FOUND {
        log:printWarn("Database credentials secret does not exist", secretName = databaseCredentialsSecretId);
        return <CredentialsNotFound>{
            body: {message: "Database credentials are not configured"}
        };
    }

    log:printError("Failed to retrieve database credentials secret", secretName = databaseCredentialsSecretId,
            errorMessage = secretError.message());
    return <CredentialsUnavailable>{
        body: {message: "Database credentials are currently unavailable"}
    };
}

# Determines whether the given error represents the secret not existing, a
# specific version of it not existing, or some other failure (e.g.
# authentication) with the secret store.
function classifySecretFetchError(secretmanager:Error secretError) returns SecretFetchFailure {
    string errorMessage = secretError.message();
    if errorMessage.includes("ResourceNotFoundException") {
        return SECRET_NOT_FOUND;
    }
    if errorMessage.includes("InvalidRequestException") && errorMessage.includes("version") {
        return VERSION_NOT_FOUND;
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
