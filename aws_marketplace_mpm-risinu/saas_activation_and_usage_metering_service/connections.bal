import ballerinax/aws.marketplace.mpm;

final mpm:Client marketplaceMeteringClient = check new ({
    region: awsRegion,
    auth: {
        accessKeyId: awsAccessKeyId,
        secretAccessKey: awsSecretAccessKey
    }
});
