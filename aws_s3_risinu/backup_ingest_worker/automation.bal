import ballerina/log;

public function main() returns error? {
    error? bucketReadyResult = ensureDestinationBucketExists();
    if bucketReadyResult is error {
        log:printError("Cannot proceed with the nightly ingest", 'error = bucketReadyResult);
        return bucketReadyResult;
    }

    string datedPath = buildDatedPath();
    IngestSummary|error summaryResult = ingestDumpFiles(datedPath);
    if summaryResult is error {
        log:printError("Cannot proceed with the nightly ingest", 'error = summaryResult);
        return summaryResult;
    }

    printIngestSummary(summaryResult);

    RetentionSweepSummary|error sweepResult = sweepRetention();
    if sweepResult is error {
        log:printError("Cannot complete the retention sweep", 'error = sweepResult);
        return sweepResult;
    }
    printRetentionSweepSummary(sweepResult);

    if summaryResult.failedCount > 0 || sweepResult.failedCount > 0 {
        return error(string `${summaryResult.failedCount} of ${summaryResult.totalFileCount} dump file(s) failed to upload, ` +
                string `${sweepResult.failedCount} of ${sweepResult.consideredCount} retention sweep move(s) failed`);
    }
}
