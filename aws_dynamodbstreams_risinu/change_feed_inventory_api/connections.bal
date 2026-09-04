import ballerinax/aws.dynamodbstreams;

final dynamodbstreams:Client dynamoDbStreamsClient = check new ({
    region: awsRegion,
    auth: {
        ssoStartUrl,
        ssoRegion,
        accountId: ssoAccountId,
        roleName: ssoRoleName
    }
});
