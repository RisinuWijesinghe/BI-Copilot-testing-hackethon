import ballerina/io;

final map<string> startupSecretIdsByName = {
    apiKey: apiKeySecretId,
    signingKey: signingKeySecretId
};

// Loaded once at module init time, before the app is considered started.
// If this fails, the module fails to initialize and the app refuses to boot.
final LoadedSecrets startupSecrets = check loadStartupSecrets(startupSecretIdsByName);

public function main() returns error? {
    io:println("Startup secrets loaded successfully: ", startupSecrets.secretValues.keys());
}
