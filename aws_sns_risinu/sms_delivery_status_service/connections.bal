import ballerinax/aws.sns;

sns:Client snsClient = check new ({
    auth: {
        accessKeyId: awsAccessKeyId,
        secretAccessKey: awsSecretAccessKey
    },
    region: awsRegion
});
