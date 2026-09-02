# A single chunk of feature usage for a customer, identified directly by the AWS account ID
# provided by sales when the deal closed, reported by the billing job.
public type UsageReportItem record {|
    # The customer's AWS account ID, as provided by sales
    string customerAwsAccountId;
    # The billing dimension (feature) that was used
    string dimension;
    # The amount of the dimension consumed
    int quantity;
    # When the usage occurred, in RFC 3339 format. Defaults to now when omitted.
    string usageTimestamp?;
|};

# The request body for reporting a batch of usage items to be billed.
public type UsageReportRequest record {|
    # Up to 25 usage items, one per customer/dimension chunk
    UsageReportItem[] usageItems;
|};

# The outcome of attempting to report a single usage item.
public type UsageItemOutcome record {|
    # The customer's AWS account ID this outcome corresponds to
    string customerAwsAccountId;
    # The billing dimension (feature) this outcome corresponds to
    string dimension;
    # The amount of the dimension consumed
    int quantity;
    # When the usage was recorded as having occurred
    string usageTimestamp;
    # ACCEPTED, DUPLICATE, NOT_SUBSCRIBED, UNPROCESSED, or REJECTED
    string outcomeStatus;
    # The AWS Marketplace metering record identifier, present only when accepted
    string meteringRecordId?;
    # A human-readable explanation of the outcome
    string message;
|};

# The response returned for a usage reporting request. Every submitted item is accounted for here.
public type UsageReportResponse record {|
    UsageItemOutcome[] itemOutcomes;
|};

# Returned when the request fails validation before anything is sent upstream.
public type UsageValidationErrorDetails record {|
    string message;
    string details;
    UsageItemOutcome[] itemOutcomes;
    string timestamp;
|};
