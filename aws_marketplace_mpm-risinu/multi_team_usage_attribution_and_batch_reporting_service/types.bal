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

# The outcome of attempting to report a single usage event, matched back to the event as
# submitted so finance can reconcile it against their own records.
public type UsageEventOutcome record {|
    # The customer's AWS account ID this outcome corresponds to
    string customerAwsAccountId;
    # The billing dimension (feature) this outcome corresponds to
    string dimension;
    # The amount of the dimension consumed
    int quantity;
    # When the usage was recorded as having occurred, as submitted
    string usageTimestamp;
    # The internal team that generated this usage, as submitted
    string internalTeam;
    # ACCEPTED, DUPLICATE, NOT_SUBSCRIBED, or UNPROCESSED
    string outcomeStatus;
    # A human-readable explanation of the outcome
    string message;
|};

# The response returned after a usage batch has been reported to AWS Marketplace. Every
# submitted event is accounted for here, matched back to its outcome.
public type UsageBatchReportResponse record {|
    # The outcome of every usage event submitted in the batch
    UsageEventOutcome[] eventOutcomes;
|};

# Returned when the request fails validation before anything is sent upstream.
public type UsageValidationErrorDetails record {|
    # A short, high-level description of the validation failure
    string message;
    # Further detail on the validation failure, such as the applicable limit
    string details;
|};

