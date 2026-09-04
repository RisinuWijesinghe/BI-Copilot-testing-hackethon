import ballerinax/aws.dynamodb;

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
