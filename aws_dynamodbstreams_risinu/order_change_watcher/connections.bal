import ballerinax/aws.dynamodb;
import ballerinax/aws.dynamodbstreams;

final dynamodb:Client dynamoDbClient = check new ({
    region: awsRegion,
    auth: {
        profileName: awsProfileName,
        credentialsFilePath: awsCredentialsFilePath
    }
});

final dynamodbstreams:Client dynamoDbStreamsClient = check new ({
    region: awsRegion,
    auth: {
        profileName: awsProfileName,
        credentialsFilePath: awsCredentialsFilePath
    }
});
