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

# Subscribes the given email address to the shared match alerts topic and records
# the subscriber in the local registry.
#
# + email - the fan's email address
# + return - the subscription result, or a clear error if it could not be completed
function subscribeFanToMatchAlerts(string email) returns SubscriptionResult|error {
    string|sns:Error subscriptionArn = snsClient->subscribe(matchAlertsTopicArn, email, sns:EMAIL);
    if subscriptionArn is sns:Error {
        return error("Unable to complete the subscription at this time. Please try again later.");
    }

    string subscriberId = uuid:createType1AsString();
    SubscriberRecord subscriberRecord = {
        subscriberId,
        email,
        subscriptionArn
    };
    subscriberRegistry[subscriberId] = subscriberRecord;

    return {
        subscriberId,
        email,
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
            email: subscriberRecord.email
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

# Publishes several distinct match alerts to the shared match alerts topic in a
# single batch call, rather than sending each one individually. SNS accepts up to
# ten entries per batch call.
#
# + alerts - the alerts to broadcast, each with a caller-chosen id
# + return - the outcome of each alert in the batch, or a clear error if the batch could not be sent at all
function broadcastMatchAlerts(AlertItem[] alerts) returns AlertOutcome[]|error {
    sns:PublishBatchRequestEntry[] entries = from AlertItem alertItem in alerts
        select {id: alertItem.id, message: alertItem.message};

    sns:PublishBatchResponse|sns:Error response = snsClient->publishBatch(matchAlertsTopicArn, entries);
    if response is sns:Error {
        return error("Unable to send the alerts at this time. Please try again later.");
    }

    AlertOutcome[] outcomes = from sns:PublishBatchResultEntry successEntry in response.successful
        select {id: successEntry.id, status: "alert sent", messageId: successEntry.messageId};

    AlertOutcome[] failures = from sns:BatchResultErrorEntry failedEntry in response.failed
        select {id: failedEntry.id, status: "alert failed", errorMessage: "Unable to send this alert. Please try again later."};

    return [...outcomes, ...failures];
}
