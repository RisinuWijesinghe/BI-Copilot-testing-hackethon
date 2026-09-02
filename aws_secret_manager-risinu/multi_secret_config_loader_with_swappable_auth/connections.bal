import ballerinax/aws.secretmanager;

final secretmanager:Client secretManagerClient = check new ({
    region: awsRegion,
    auth: {
        accessKeyId: awsAccessKeyId,
        secretAccessKey: awsSecretAccessKey
    }
});
