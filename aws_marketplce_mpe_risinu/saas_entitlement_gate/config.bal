import ballerinax/aws;

# AWS region hosting the Marketplace Entitlement Service for this seller account.
configurable aws:Region|string awsRegion = ?;

# IAM access key ID used to authenticate against AWS Marketplace Entitlement Service.
configurable string awsAccessKeyId = ?;

# IAM secret access key used to authenticate against AWS Marketplace Entitlement Service.
configurable string awsSecretAccessKey = ?;

# The AWS Marketplace product code this entitlement gate reports on.
configurable string productCode = ?;

# Port on which the entitlement gate HTTP service listens.
configurable int servicePort = 8080;
