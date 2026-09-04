import ballerinax/aws.dynamodb;
import ballerinax/aws.dynamodbstreams;

final dynamodb:Client dynamoDbClient = check new ({
    region: awsRegion,
    auth: {
        roleArn: roleArnToAssume,
        sourceCredentials: {
            accessKeyId: sourceAccessKeyId,
            secretAccessKey: sourceSecretAccessKey
        }
    }
});

final dynamodbstreams:Client dynamoDbStreamsClient = check new ({
    region: awsRegion,
    auth: {
        roleArn: roleArnToAssume,
        sourceCredentials: {
            accessKeyId: sourceAccessKeyId,
            secretAccessKey: sourceSecretAccessKey
        }
    }
});
