import ballerinax/aws.dynamodb;
import ballerinax/aws.dynamodbstreams;

// The AWS clients are created lazily, on first actual use, rather than eagerly at module load. This keeps the
// watcher's pure logic (narration, filtering, stats) testable without AWS credentials or any call to AWS.
isolated dynamodb:Client? cachedDynamoDbClient = ();
isolated dynamodbstreams:Client? cachedDynamoDbStreamsClient = ();

# Returns the DynamoDB client, creating it on first use.
#
# + return - the DynamoDB client, or an error if it could not be created
isolated function getDynamoDbClient() returns dynamodb:Client|error {
    lock {
        dynamodb:Client? existingClient = cachedDynamoDbClient;
        if existingClient is dynamodb:Client {
            return existingClient;
        }
        dynamodb:Client newClient = check new ({
            region: awsRegion,
            auth: {
                profileName: awsProfileName,
                credentialsFilePath: awsCredentialsFilePath
            }
        });
        cachedDynamoDbClient = newClient;
        return newClient;
    }
}

# Returns the DynamoDB Streams client, creating it on first use.
#
# + return - the DynamoDB Streams client, or an error if it could not be created
isolated function getDynamoDbStreamsClient() returns dynamodbstreams:Client|error {
    lock {
        dynamodbstreams:Client? existingClient = cachedDynamoDbStreamsClient;
        if existingClient is dynamodbstreams:Client {
            return existingClient;
        }
        dynamodbstreams:Client newClient = check new ({
            region: awsRegion,
            auth: {
                profileName: awsProfileName,
                credentialsFilePath: awsCredentialsFilePath
            }
        });
        cachedDynamoDbStreamsClient = newClient;
        return newClient;
    }
}
