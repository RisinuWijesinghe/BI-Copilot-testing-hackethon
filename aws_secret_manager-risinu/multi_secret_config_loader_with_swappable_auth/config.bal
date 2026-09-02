// Selects the auth method used to talk to the secret store. Local development
// uses a plain access-key/secret-key pair; staging and production assume an
// IAM role instead, so no long-lived keys are involved.
configurable "local"|"staging"|"production" appEnvironment = "local";
configurable string awsRegion = "us-east-1";

// Local development only: a plain AWS access key / secret key pair, expected
// to be supplied via environment variables.
configurable string? localAwsAccessKeyId = ();
configurable string? localAwsSecretAccessKey = ();

// Staging/production only: the ARN of the IAM role this app should assume,
// selected based on which environment it is running in.
configurable string? stagingRoleArn = ();
configurable string? productionRoleArn = ();

// Logical name -> AWS secret ID mapping for the secrets this app needs at boot.
configurable string apiKeySecretId = ?;
configurable string signingKeySecretId = ?;
configurable string webhookSigningSecretId = ?;
