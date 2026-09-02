import ballerinax/aws;

# AWS region hosting the Marketplace Entitlement Service for this seller account.
configurable aws:Region|string awsRegion = ?;

# IAM access key ID used to authenticate against AWS Marketplace Entitlement Service.
configurable string awsAccessKeyId = ?;

# IAM secret access key used to authenticate against AWS Marketplace Entitlement Service.
configurable string awsSecretAccessKey = ?;

# Product codes this reporting service is allowed to report on.
configurable string[] supportedProductCodes = ?;

# Dimensions sold for the supported products. Used to validate caller-supplied dimension filters.
configurable string[] supportedDimensions = ?;

# Maximum number of entitlement records requested per page when sweeping AWS Marketplace.
configurable int entitlementPageSize = 20;

# How often, in seconds, the background job refreshes the entitlement snapshot for every configured product.
configurable decimal refreshIntervalSeconds = 300;

# Port on which the internal reporting HTTP service listens.
configurable int servicePort = 8080;
