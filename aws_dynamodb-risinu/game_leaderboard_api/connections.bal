import ballerinax/aws.dynamodb;

final dynamodb:Client dynamoDbClient = check new ({
    region: awsRegion,
    auth: {
        accessKeyId: awsAccessKeyId,
        secretAccessKey: awsSecretAccessKey
    }
});
