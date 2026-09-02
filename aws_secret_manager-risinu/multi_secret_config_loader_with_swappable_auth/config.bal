// Local development auth: a plain AWS access key / secret key pair, expected
// to be supplied via environment variables (e.g. BAL_CONFIG_FILES or
// the standard BALCONF_-style env var overrides for configurables).
configurable string awsAccessKeyId = ?;
configurable string awsSecretAccessKey = ?;
configurable string awsRegion = "us-east-1";

// Logical name -> AWS secret ID mapping for the secrets this app needs at boot.
configurable string apiKeySecretId = ?;
configurable string signingKeySecretId = ?;
configurable string webhookSigningSecretId = ?;
