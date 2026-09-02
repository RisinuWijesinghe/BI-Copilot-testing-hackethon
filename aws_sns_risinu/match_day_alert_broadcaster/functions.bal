import ballerina/lang.regexp;
import ballerinax/aws.sns;

// Simple, practical email format check.
final regexp:RegExp EMAIL_PATTERN = re `^[^\s@]+@[^\s@]+\.[^\s@]+$`;

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

# Subscribes the given email address to the shared match alerts topic.
#
# + email - the fan's email address
# + return - the subscription result, or a clear error if it could not be completed
function subscribeFanToMatchAlerts(string email) returns SubscriptionResult|error {
    string|sns:Error result = snsClient->subscribe(matchAlertsTopicArn, email, sns:EMAIL);
    if result is sns:Error {
        return error("Unable to complete the subscription at this time. Please try again later.");
    }
    return {email: email, status: "subscription pending confirmation"};
}

# Publishes a match alert message to the shared match alerts topic.
#
# + message - the alert text to broadcast
# + return - the publish result, or a clear error if the alert could not be sent
function broadcastMatchAlert(string message) returns AlertResult|error {
    sns:PublishMessageResponse|sns:Error result = snsClient->publish(matchAlertsTopicArn, message, sns:TOPIC);
    if result is sns:Error {
        return error("Unable to send the alert at this time. Please try again later.");
    }
    return {status: "alert sent", messageId: result.messageId};
}
