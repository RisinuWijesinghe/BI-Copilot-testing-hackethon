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

// The outcome of archiving a single aged backup object.
public type ArchiveMoveResult record {|
    string objectKey;
    boolean succeeded;
    string reason?;
|};

// The overall outcome of a retention sweep.
public type RetentionSweepSummary record {|
    int consideredCount;
    int movedCount;
    int failedCount;
    ArchiveMoveResult[] results;
|};
