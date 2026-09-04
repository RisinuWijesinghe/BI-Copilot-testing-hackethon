# Represents a single DynamoDB table that has a change feed (DynamoDB Streams) enabled.
public type ChangeFeedEntry record {|
    # Name of the DynamoDB table
    string tableName;
    # Identifier (ARN) of the table's change feed
    string streamId;
    # Timestamp label AWS attaches to the change feed
    string streamLabel;
|};

# Generic error response returned when the upstream change feed service cannot be reached.
public type ChangeFeedServiceError record {|
    string message;
|};

# Error response returned when the requested table has no change feed.
public type ChangeFeedNotFoundError record {|
    string message;
|};

# Error response returned when the request is malformed.
public type ChangeFeedBadRequestError record {|
    string message;
|};

# Current lifecycle status of a change feed.
public enum ChangeFeedStatus {
    CHANGE_FEED_ENABLING = "ENABLING",
    CHANGE_FEED_LIVE = "LIVE",
    CHANGE_FEED_DISABLING = "DISABLING",
    CHANGE_FEED_OFF = "OFF"
}

# What item data each change record carries.
public enum ChangeFeedViewType {
    KEYS_ONLY = "KEYS_ONLY",
    NEW_IMAGE = "NEW_IMAGE",
    OLD_IMAGE = "OLD_IMAGE",
    NEW_AND_OLD_IMAGES = "NEW_AND_OLD_IMAGES"
}


# One attribute of a table's primary key.
public type KeyAttribute record {|
    # Name of the attribute
    string attributeName;
    # Whether this attribute is the partition key
    boolean partitionKey;
|};

# Shard composition of a change feed.
public type ShardSummary record {|
    # Total number of shards the feed currently has
    int totalShards;
    # Number of shards still accepting writes
    int openShards;
    # Number of shards that are already closed
    int closedShards;
|};

# Detailed view of a single table's change feed.
public type ChangeFeedDetail record {|
    # Name of the DynamoDB table
    string tableName;
    # Identifier (ARN) of the table's change feed
    string streamId;
    # Timestamp label AWS attaches to the change feed
    string streamLabel;
    # Current lifecycle status of the change feed
    ChangeFeedStatus status;
    # What item data each change record carries
    ChangeFeedViewType viewType;
    # The attributes that make up the table's primary key
    KeyAttribute[] keyAttributes;
    # How the feed is currently split across shards
    ShardSummary shards;
|};
