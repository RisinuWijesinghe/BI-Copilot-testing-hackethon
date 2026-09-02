import ballerinax/aws.marketplace.mpm;

final mpm:Client marketplaceMeteringClient = check initializeMarketplaceMeteringClient();

function initializeMarketplaceMeteringClient() returns mpm:Client|error {
    return new ({
        region: awsRegion,
        auth: {
            accessKeyId: awsAccessKeyId,
            secretAccessKey: awsSecretAccessKey
        }
    });
}

