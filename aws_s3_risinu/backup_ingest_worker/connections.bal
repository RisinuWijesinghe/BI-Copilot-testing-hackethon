import ballerinax/aws.s3;

final s3:Client s3Client = check new ({
    region: region,
    auth: {
        accessKeyId,
        secretAccessKey
    }
});
