// AWS region and credentials the service uses to talk to AWS Secrets Manager.
configurable string awsRegion = "us-east-1";
configurable string awsAccessKeyId = ?;
configurable string awsSecretAccessKey = ?;

// Fixed secret name under which the database credentials JSON blob is stored.
configurable string databaseCredentialsSecretId = ?;

// Port the HTTP service listens on.
configurable int servicePort = 9090;
