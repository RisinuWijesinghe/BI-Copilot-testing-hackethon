import ballerinax/aws.marketplace.mpe;

final mpe:Client entitlementClient = check new ({
    region: awsRegion,
    auth: {
        accessKeyId: awsAccessKeyId,
        secretAccessKey: awsSecretAccessKey
    }
});
