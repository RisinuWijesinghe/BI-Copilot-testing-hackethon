import ballerinax/aws.secretmanager;

final secretmanager:Client secretManagerClient = check new ({
    region: awsRegion,
    auth: {
        roleArn: webIdentityRoleArn,
        webIdentityTokenFile: webIdentityTokenFile
    }
});

