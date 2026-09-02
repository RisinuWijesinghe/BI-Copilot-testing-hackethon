# Registration token supplied by a new customer after subscribing via AWS Marketplace.
public type ActivationRequest record {|
    # The registration token returned by AWS Marketplace on subscription
    string registrationToken;
|};

# Customer identifying details resolved from a valid registration token, used to activate the account.
public type CustomerActivationDetails record {|
    # The AWS account identifier of the customer
    string customerAwsAccountId;
    # The unique customer identifier to associate with the activated account
    string customerIdentifier;
    # The AWS Marketplace product code the customer subscribed to
    string productCode;
|};

# A clear, caller-facing error payload returned for invalid or expired registration tokens.
public type ActivationErrorDetails record {|
    string message;
    string details;
    string timestamp;
|};

# A single chunk of feature usage for an already-activated customer, reported by the billing job.
public type UsageReportItem record {|
    # The customer identifier obtained during activation
    string customerIdentifier;
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
    # The customer identifier this outcome corresponds to
    string customerIdentifier;
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
