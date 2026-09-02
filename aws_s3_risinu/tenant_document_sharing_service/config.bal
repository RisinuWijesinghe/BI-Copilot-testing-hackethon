import ballerinax/aws;

configurable string bucketName = ?;
configurable aws:Region region = ?;
configurable string accessKeyId = ?;
configurable string secretAccessKey = ?;

configurable int servicePort = 8080;
configurable int defaultLinkExpirationMinutes = 15;
configurable int maxLinkExpirationMinutes = 60;
configurable string[] allowedUploadContentTypes = ["application/pdf", "image/png", "image/jpeg"];
