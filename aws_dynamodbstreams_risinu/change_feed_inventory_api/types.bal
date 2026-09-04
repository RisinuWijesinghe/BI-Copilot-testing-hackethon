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
