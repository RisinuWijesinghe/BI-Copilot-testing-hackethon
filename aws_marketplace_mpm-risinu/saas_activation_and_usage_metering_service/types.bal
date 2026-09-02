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
