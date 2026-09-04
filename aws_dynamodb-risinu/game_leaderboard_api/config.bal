// AWS profile and region — must come from configuration, never hard-coded.
configurable string awsProfileName = ?;
configurable string awsRegion = ?;

// DynamoDB table used to store leaderboard entries. Provisioned externally by Terraform.
configurable string leaderboardTableName = "GameLeaderboard";

// HTTP listener port.
configurable int servicePort = 8080;
