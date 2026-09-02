// Payload handed over by the scheduled job: a fixed batch of pending order
// IDs that need to be reconciled.
public type OrderReconciliationEvent record {|
    string[] orderIds;
|};

// Summary of a batch processing invocation.
public type BatchSummary record {|
    int totalMessages;
    int processedCount;
    int rejectedCount;
    int deadlineTimestamp;
|};

// Health-check response reporting runtime/invocation diagnostics.
public type HealthStatus record {|
    string status;
    string requestId;
    int remainingExecutionTimeMs;
|};
