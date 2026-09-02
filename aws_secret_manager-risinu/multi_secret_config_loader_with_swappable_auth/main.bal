import ballerina/io;

final map<string> startupSecretIdsByName = {
    apiKey: apiKeySecretId,
    signingKey: signingKeySecretId,
    webhookSigningSecret: webhookSigningSecretId
};

// Loaded once at module init time, before the app is considered started.
// If this fails, the module fails to initialize and the app refuses to boot.
// Kept as the in-memory cache for the lifetime of the app - the rest of the
// app reads from this synchronously instead of calling the secret store again.
final LoadedSecrets startupSecrets = check loadStartupSecrets(startupSecretIdsByName);

public function main() returns error? {
    io:println("Startup secrets loaded successfully: ", startupSecrets.secretValues.keys());
}
