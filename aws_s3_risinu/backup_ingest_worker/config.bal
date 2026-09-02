import ballerinax/aws;

configurable string bucketName = ?;
configurable aws:Region region = ?;
configurable string accessKeyId = ?;
configurable string secretAccessKey = ?;

configurable string dumpDirectoryPath = ?;

// Files at or above this size are uploaded in parts instead of being read into memory all at once.
configurable int multipartThresholdInBytes = 104857600;

// Size, in bytes, of each part sent during a multipart upload. Must be at least 5 MiB, the
// minimum S3 allows for any part other than the last one.
configurable int multipartChunkSizeInBytes = 8388608;
