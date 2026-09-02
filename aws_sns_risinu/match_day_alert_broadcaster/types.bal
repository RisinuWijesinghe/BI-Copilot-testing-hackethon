import ballerina/http;

# Request payload for subscribing a fan's email to match alerts.
public type SubscriptionRequest record {|
    string email;
|};

# Request payload for broadcasting a match alert.
public type AlertRequest record {|
    string message;
|};

# Response returned when a subscription request succeeds.
public type SubscriptionAccepted record {|
    *http:Accepted;
    SubscriptionResult body;
|};

# Body of a successful subscription response.
public type SubscriptionResult record {|
    string email;
    string status;
|};

# Response returned when an alert has been broadcast successfully.
public type AlertSent record {|
    *http:Ok;
    AlertResult body;
|};

# Body of a successful alert broadcast response.
public type AlertResult record {|
    string status;
    string messageId;
|};

# A clear, user-facing error body — never exposes internal error details.
public type ErrorDetails record {|
    string message;
|};

# Response returned when a request fails validation (e.g. an unusable email).
public type InvalidRequest record {|
    *http:BadRequest;
    ErrorDetails body;
|};

# Response returned when the alert or subscription could not be processed.
public type ProcessingFailed record {|
    *http:InternalServerError;
    ErrorDetails body;
|};
