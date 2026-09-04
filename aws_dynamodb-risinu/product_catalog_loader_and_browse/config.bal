// AWS region the DynamoDB table lives in.
configurable string awsRegion = ?;

// DynamoDB table holding the product catalog. Provisioned externally; this service only reads and writes it.
configurable string catalogTableName = ?;

// HTTP listener port.
configurable int servicePort = 8080;
