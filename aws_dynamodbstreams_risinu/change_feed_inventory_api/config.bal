// AWS region the DynamoDB tables live in.
configurable string awsRegion = ?;

// IAM role to assume via AWS STS in order to obtain temporary credentials.
configurable string roleArnToAssume = ?;

// Base (source) credentials used to call AWS STS AssumeRole.
configurable string sourceAccessKeyId = ?;
configurable string sourceSecretAccessKey = ?;

// Port the change feed inventory HTTP API listens on.
configurable int servicePort = 8080;
