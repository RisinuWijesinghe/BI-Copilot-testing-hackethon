// Represents a single order extracted from an SQS message body.
public type OrderRecord record {|
    string orderId;
    string customerId;
    decimal totalAmount;
|};

// Summary of a batch processing invocation.
public type BatchSummary record {|
    int totalMessages;
    int processedCount;
    int rejectedCount;
|};

// Health-check response reporting runtime/invocation diagnostics.
public type HealthStatus record {|
    string status;
    string requestId;
    int remainingExecutionTimeMs;
|};
