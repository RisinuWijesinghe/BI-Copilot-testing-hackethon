import ballerinax/aws.secretmanager;

// Loads all named secrets required at startup in a single batch call.
// - If the secret store rejects our credentials, fails fast with a clear
//   authentication error.
// - If one or more requested secrets do not exist, fails fast reporting
//   exactly which named secrets are missing.
function loadStartupSecrets(map<string> secretIdsByName) returns LoadedSecrets|error {
    string[] secretIds = secretIdsByName.toArray();

    secretmanager:BatchGetSecretValueResponse|secretmanager:Error response =
        secretManagerClient->batchGetSecretValue(secretIds = secretIds);

    if response is secretmanager:Error {
        return error(string `Can't authenticate to secret store: ${response.message()}`, response);
    }

    secretmanager:ApiError[]? apiErrors = response.errors;
    if apiErrors is secretmanager:ApiError[] && apiErrors.length() > 0 {
        string[] missingSecretDetails = [];
        foreach secretmanager:ApiError apiError in apiErrors {
            string? failedSecretId = apiError.secretId;
            string secretName = failedSecretId is string ? resolveSecretName(secretIdsByName, failedSecretId) : "unknown";
            string errorCode = apiError.errorCode ?: "UnknownError";
            string errorMessage = apiError.message ?: "no additional details";
            missingSecretDetails.push(string `"${secretName}" (secretId: ${failedSecretId ?: "unknown"}, code: ${errorCode}, message: ${errorMessage})`);
        }
        string joinedDetails = string:'join("; ", ...missingSecretDetails);
        return error(string `Failed to load required secret(s) at startup: ${joinedDetails}`);
    }

    secretmanager:SecretValue[]? secretValues = response.secretValues;
    if secretValues is () {
        return error("Failed to load required secret(s) at startup: secret store returned no values");
    }

    map<string> loadedByName = {};
    foreach secretmanager:SecretValue secretValue in secretValues {
        string secretName = resolveSecretName(secretIdsByName, secretValue.name);
        byte[]|string value = secretValue.value;
        string resolvedValue = value is string ? value : check string:fromBytes(value);
        loadedByName[secretName] = resolvedValue;
    }

    string[] missingNames = [];
    foreach string secretName in secretIdsByName.keys() {
        if !loadedByName.hasKey(secretName) {
            missingNames.push(secretName);
        }
    }
    if missingNames.length() > 0 {
        string joinedNames = string:'join(", ", ...missingNames);
        return error(string `Failed to load required secret(s) at startup: no value returned for "${joinedNames}"`);
    }

    return {secretValues: loadedByName};
}

// Resolves the logical secret name (e.g. "apiKey") for a given AWS secret ID,
// falling back to the raw ID itself if no mapping is found.
function resolveSecretName(map<string> secretIdsByName, string secretId) returns string {
    foreach [string, string] [name, id] in secretIdsByName.entries() {
        if id == secretId {
            return name;
        }
    }
    return secretId;
}

// Synchronous read from the in-memory cache populated at startup. Since the
// secrets were already loaded (and validated) before the app was considered
// started, this never needs to contact the secret store again.
public function getCachedSecret(string secretName) returns string|error {
    string? secretValue = startupSecrets.secretValues[secretName];
    if secretValue is () {
        return error(string `No cached secret found for "${secretName}"`);
    }
    return secretValue;
}
