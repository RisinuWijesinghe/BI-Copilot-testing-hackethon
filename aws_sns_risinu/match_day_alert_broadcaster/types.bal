import ballerina/http;

# What kind of match updates a fan wants to receive.
public enum AlertPreference {
    GOAL,
    ALL
}

# What kind of event a broadcast alert is about.
public enum EventType {
    GOAL,
    HALF_TIME,
    FULL_TIME,
    KICK_OFF,
    OTHER
}

# Request payload for subscribing a fan's email to match alerts.
public type SubscriptionRequest record {|
    string email;
    AlertPreference preference = ALL;
|};

# Request payload for broadcasting a match alert.
public type AlertRequest record {|
    EventType eventType;
    string message;
|};

# A subscribed fan, as tracked in the broadcaster's own registry.
public type Subscriber record {|
    string subscriberId;
    string email;
    AlertPreference preference;
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
    AlertPreference preference;
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
