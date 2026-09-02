import ballerinax/aws.sns;

final sns:Client snsClient = check new ({
    auth: {
        accessKeyId: awsAccessKeyId,
        secretAccessKey: awsSecretAccessKey
    },
    region: awsRegion
});
