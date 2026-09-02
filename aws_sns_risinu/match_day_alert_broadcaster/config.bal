// AWS credentials and region used to connect to Amazon SNS.
configurable string awsAccessKeyId = ?;
configurable string awsSecretAccessKey = ?;
configurable string awsRegion = ?;

// ARN of the shared SNS topic that fans are subscribed to for match alerts.
configurable string matchAlertsTopicArn = ?;
