import ballerinax/aws;
import ballerinax/aws.s3;

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

// Backups older than this many days are swept into the long-term archive area.
configurable int retentionDays = 30;

// S3 key prefix under which archived (long-term) backups are stored.
configurable string archiveKeyPrefix = "archive/";

// Storage class used for archived (long-term) backups. A cheaper, infrequent-access tier.
configurable s3:StorageClass archiveStorageClass = s3:GLACIER;
