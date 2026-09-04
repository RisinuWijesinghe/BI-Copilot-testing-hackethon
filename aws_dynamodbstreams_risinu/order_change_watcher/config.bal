// AWS region the Orders table and its change feed live in.
configurable string awsRegion = ?;

// Name of the Orders table to watch.
configurable string ordersTableName = ?;

// Named profile in the local AWS credentials file used to authenticate.
configurable string awsProfileName = ?;

// Path to the local AWS credentials file. Defaults to the standard location.
configurable string awsCredentialsFilePath = "~/.aws/credentials";

// How long to wait between polls of a shard that had nothing to report.
configurable decimal pollIntervalSeconds = 2;

// How often to re-check the feed's shard topology for newly created shards, so a reshard (a shard closing and
// being replaced by new ones) is picked up instead of the watcher just going quiet.
configurable decimal shardDiscoveryIntervalSeconds = 15;

// Port the watcher's running-stats HTTP endpoint listens on.
configurable int statsServicePort = 8080;
