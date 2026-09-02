import ballerina/io;

final map<string> startupSecretIdsByName = {
    apiKey: apiKeySecretId,
    signingKey: signingKeySecretId,
    webhookSigningSecret: webhookSigningSecretId
};

public function main() returns error? {
    // Loaded once at boot, before the app is considered started. If this
    // fails, main returns an error and the app refuses to start rather than
    // run in a broken state.
    startupSecrets = check loadStartupSecrets(startupSecretIdsByName);

    io:println("Startup secrets loaded successfully: ", startupSecrets.secretValues.keys());
}
