import ballerinax/aws;

configurable string bucketName = ?;
configurable aws:Region region = ?;
configurable string accessKeyId = ?;
configurable string secretAccessKey = ?;

configurable int servicePort = 8080;
configurable int downloadLinkExpirationMinutes = 15;
