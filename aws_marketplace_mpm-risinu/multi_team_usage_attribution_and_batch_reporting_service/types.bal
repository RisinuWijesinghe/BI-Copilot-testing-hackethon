# A single unit of feature usage collected from one of the internal teams sharing the
# AWS Marketplace product, submitted by the finance team for batch reporting.
public type TeamUsageEvent record {|
    # The customer's AWS account ID this usage applies to
    string customerAwsAccountId;
    # The billing dimension (feature) that was used
    string dimension;
    # The amount of the dimension consumed
    int quantity;
    # When the usage occurred, in RFC 3339 format
    string usageTimestamp;
    # The internal team that generated this usage, for later cost reconciliation
    string internalTeam;
|};

# The request body for reporting a batch of usage events collected across internal teams.
public type UsageBatchReportRequest record {|
    # The usage events to report to AWS Marketplace in a single batch
    TeamUsageEvent[] usageEvents;
|};

# The response returned after a usage batch has been reported to AWS Marketplace.
public type UsageBatchReportResponse record {|
    # The number of usage events accepted by AWS Marketplace for billing
    int acceptedCount;
    # The total number of usage events submitted in the batch
    int totalCount;
|};

