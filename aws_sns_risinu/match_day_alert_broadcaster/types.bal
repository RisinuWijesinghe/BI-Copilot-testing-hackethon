import ballerina/http;

# Request payload for subscribing a fan's email to match alerts.
public type SubscriptionRequest record {|
    string email;
|};

# A single alert to be broadcast, identified by a caller-chosen id so the outcome
# of each one can be reported back individually.
public type AlertItem record {|
    string id;
    string message;
|};

# Request payload for broadcasting a batch of match alerts in a single call.
public type AlertBatchRequest record {|
    AlertItem[] alerts;
|};

# A subscribed fan, as tracked in the broadcaster's own registry.
public type Subscriber record {|
    string subscriberId;
    string email;
|};

# Internal registry record — carries the SNS subscription ARN in addition to the public fields.
type SubscriberRecord record {|
    *Subscriber;
    string subscriptionArn;
|};

# Response returned when a subscription request succeeds.
public type SubscriptionAccepted record {|
    *http:Accepted;
    SubscriptionResult body;
|};

# Body of a successful subscription response.
public type SubscriptionResult record {|
    string subscriberId;
    string email;
    string status;
|};

# Response returned when a batch of alerts has been broadcast, reporting the outcome
# of each individual alert in the batch.
public type AlertBatchSent record {|
    *http:Ok;
    AlertBatchResult body;
|};

# The outcome of a single alert within a broadcast batch.
public type AlertOutcome record {|
    string id;
    string status;
    string messageId?;
    string errorMessage?;
|};

# Body of a batch alert broadcast response.
public type AlertBatchResult record {|
    AlertOutcome[] results;
|};

# Response returned with the list of current subscribers.
public type SubscriberList record {|
    *http:Ok;
    Subscriber[] body;
|};

# Response returned when a fan successfully unsubscribes.
public type UnsubscribeConfirmed record {|
    *http:Ok;
    record {| string status; |} body;
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

# Response returned when the referenced subscriber cannot be found.
public type SubscriberNotFound record {|
    *http:NotFound;
    ErrorDetails body;
|};

# Response returned when the alert or subscription could not be processed.
public type ProcessingFailed record {|
    *http:InternalServerError;
    ErrorDetails body;
|};
