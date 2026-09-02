// The outcome of uploading a single local dump file to S3.
public type FileUploadResult record {|
    string fileName;
    boolean succeeded;
    string reason?;
|};

// The overall outcome of a nightly ingest run.
public type IngestSummary record {|
    string bucketName;
    string datedPath;
    int totalFileCount;
    int succeededCount;
    int failedCount;
    FileUploadResult[] results;
|};
