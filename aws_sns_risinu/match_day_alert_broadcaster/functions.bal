import ballerina/lang.regexp;
import ballerina/uuid;
import ballerinax/aws.sns;

// Simple, practical email format check.
final regexp:RegExp EMAIL_PATTERN = check regexp:fromString("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$");

// In-memory registry of current subscribers, keyed by the subscriber id we issue.
// This backs the list/unsubscribe endpoints since SNS subscription ARNs are not
// convenient identifiers to hand back to callers.
final map<SubscriberRecord> subscriberRegistry = {};

# Checks whether the given string is a usable email address.
#
# + email - the email address to validate
# + return - true if the email looks usable, false otherwise
function isValidEmail(string email) returns boolean {
    string trimmedEmail = email.trim();
    if trimmedEmail.length() == 0 {
        return false;
    }
    return EMAIL_PATTERN.isFullMatch(trimmedEmail);
}

# Builds the SNS filter policy for a given alert preference. Fans who only want goals
# get a policy that matches only the GOAL event type; fans who want everything get no
# filter policy at all, so every published alert reaches them.
#
# + preference - the fan's chosen alert preference
# + return - the filter policy json to set on the subscription, or () if none is needed
function buildFilterPolicy(AlertPreference preference) returns json? {
    if preference == GOAL {
        return {"eventType": ["GOAL"]};
    }
    return ();
}

# Subscribes the given email address to the shared match alerts topic, honoring the
# fan's alert preference via an SNS subscription filter policy, and records the
# subscriber in the local registry.
#
# + email - the fan's email address
# + preference - the kind of updates the fan wants to receive
# + return - the subscription result, or a clear error if it could not be completed
function subscribeFanToMatchAlerts(string email, AlertPreference preference) returns SubscriptionResult|error {
    string|sns:Error subscriptionArn = snsClient->subscribe(matchAlertsTopicArn, email, sns:EMAIL);
    if subscriptionArn is sns:Error {
        return error("Unable to complete the subscription at this time. Please try again later.");
    }

    json? filterPolicy = buildFilterPolicy(preference);
    if filterPolicy is json {
        sns:Error? attributeResult = snsClient->setSubscriptionAttributes(subscriptionArn, sns:FILTER_POLICY, filterPolicy);
        if attributeResult is sns:Error {
            return error("Unable to complete the subscription at this time. Please try again later.");
        }
    }

    string subscriberId = uuid:createType1AsString();
    SubscriberRecord subscriberRecord = {
        subscriberId,
        email,
        preference,
        subscriptionArn
    };
    subscriberRegistry[subscriberId] = subscriberRecord;

    return {
        subscriberId,
        email,
        preference,
        status: "subscription pending confirmation"
    };
}

# Lists everyone currently tracked as subscribed in the local registry.
#
# + return - the list of current subscribers
function listCurrentSubscribers() returns Subscriber[] {
    return from SubscriberRecord subscriberRecord in subscriberRegistry.toArray()
        select {
            subscriberId: subscriberRecord.subscriberId,
            email: subscriberRecord.email,
            preference: subscriberRecord.preference
        };
}

# Removes a fan's subscription using the identifier issued at signup.
#
# + subscriberId - the identifier returned when the fan subscribed
# + return - true if the subscriber was found and removed, false if the identifier is unknown, or an error if removal failed
function unsubscribeFan(string subscriberId) returns boolean|error {
    SubscriberRecord? subscriberRecord = subscriberRegistry[subscriberId];
    if subscriberRecord is () {
        return false;
    }

    sns:Error? result = snsClient->unsubscribe(subscriberRecord.subscriptionArn);
    if result is sns:Error {
        return error("Unable to unsubscribe at this time. Please try again later.");
    }

    _ = subscriberRegistry.remove(subscriberId);
    return true;
}

# Publishes a match alert message, tagged with its event type, to the shared match
# alerts topic. SNS subscription filter policies ensure only fans who asked for that
# kind of update are actually notified.
#
# + eventType - the kind of event the alert is about
# + message - the alert text to broadcast
# + return - the publish result, or a clear error if the alert could not be sent
function broadcastMatchAlert(EventType eventType, string message) returns AlertResult|error {
    map<sns:MessageAttributeValue> attributes = {
        "eventType": eventType
    };
    sns:PublishMessageResponse|sns:Error result =
        snsClient->publish(matchAlertsTopicArn, message, sns:TOPIC, attributes);
    if result is sns:Error {
        return error("Unable to send the alert at this time. Please try again later.");
    }
    return {status: "alert sent", messageId: result.messageId};
}
