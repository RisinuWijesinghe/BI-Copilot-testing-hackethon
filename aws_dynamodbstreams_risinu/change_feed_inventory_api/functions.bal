import ballerinax/aws.dynamodb;

// Generic, caller-safe message. AWS error details, request identifiers, and credentials must never surface here.
const string CHANGE_FEED_SERVICE_UNREACHABLE = "unable to reach the change feed service";

# Retrieves the change feed (DynamoDB Streams) entries for every table in the account.
# Iterates the full account-wide table listing, page by page, and describes each table to
# determine whether it has a change feed enabled.
#
# + return - the list of change feed entries, or an error if AWS could not be reached
function getChangeFeedEntries() returns ChangeFeedEntry[]|error {
    stream<string, dynamodb:Error?> tableNames = check dynamoDbClient->listTables();

    ChangeFeedEntry[] changeFeedEntries = [];
    check from string tableName in tableNames
        do {
            dynamodb:TableDescription tableDescription = check dynamoDbClient->describeTable(tableName);
            dynamodb:StreamSpecification? streamSpecification = tableDescription?.StreamSpecification;
            if streamSpecification is dynamodb:StreamSpecification && streamSpecification.StreamEnabled {
                string? streamId = tableDescription?.LastDecreaseDateTimeatestStreamArn;
                string? streamLabel = tableDescription?.LatestStreamLabel;
                if streamId is string && streamLabel is string {
                    changeFeedEntries.push({
                        tableName,
                        streamId,
                        streamLabel
                    });
                }
            }
        };
    return changeFeedEntries;
}
