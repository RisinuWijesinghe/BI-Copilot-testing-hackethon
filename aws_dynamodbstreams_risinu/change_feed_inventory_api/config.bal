// AWS region the DynamoDB change feeds live in.
configurable string awsRegion = ?;

// IAM Identity Center (SSO) session details used to obtain credentials.
configurable string ssoStartUrl = ?;
configurable string ssoRegion = ?;
configurable string ssoAccountId = ?;
configurable string ssoRoleName = ?;

// Port the change feed inventory HTTP API listens on.
configurable int servicePort = 8080;
