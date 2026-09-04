// AWS region the Orders table and its change feed live in.
configurable string awsRegion = ?;

// Name of the Orders table to watch.
configurable string ordersTableName = ?;

// Named profile in the local AWS credentials file used to authenticate.
configurable string awsProfileName = ?;

// Path to the local AWS credentials file. Defaults to the standard location.
configurable string awsCredentialsFilePath = "~/.aws/credentials";

// How long the feed may stay quiet (no new records on any shard) before the watcher finishes.
configurable decimal idleTimeoutSeconds = 30;

// How long to wait between polls of a shard that had nothing to report.
configurable decimal pollIntervalSeconds = 2;
