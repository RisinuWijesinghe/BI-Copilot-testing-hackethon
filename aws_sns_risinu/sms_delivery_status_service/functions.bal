import ballerina/lang.regexp;
import ballerinax/aws.sns;

# Error raised when an invalid setting value is supplied.
public type InvalidSettingError distinct error;

// A practical sender name check: 1-11 alphanumeric characters, matching the constraint
// AWS itself enforces on the SMS default sender ID.
final regexp:RegExp SENDER_NAME_PATTERN = check regexp:fromString("^[A-Za-z0-9]{1,11}$");

# Retrieves the current account-wide SMS sending settings.
#
# + return - the current account settings, or a clear error if they could not be retrieved
function getAccountSettings() returns AccountSettings|error {
    sns:SMSAttributes|sns:Error attributes = snsClient->getSMSAttributes();
    if attributes is sns:Error {
        return error("Unable to retrieve account settings at this time. Please try again later.");
    }

    int? monthlySpendLimit = attributes.monthlySpendLimit;
    string? defaultSenderName = attributes.defaultSenderID;

    return {
        monthlySpendLimit: monthlySpendLimit is int ? monthlySpendLimit : 0,
        defaultSenderName: defaultSenderName is string ? defaultSenderName : ""
    };
}

# Updates the account-wide SMS sending settings, such as the monthly spending cap and the
# default sender name used on outgoing messages.
#
# + request - the new settings to apply
# + return - the updated settings, an InvalidSettingError if a supplied value is not usable,
#            or a clear error if the update could not be completed
function updateAccountSettings(UpdateAccountSettingsRequest request) returns AccountSettings|InvalidSettingError|error {
    int monthlySpendLimit = request.monthlySpendLimit;
    if monthlySpendLimit <= 0 {
        return error InvalidSettingError("The monthly spend limit must be a positive amount.");
    }

    string defaultSenderName = request.defaultSenderName;
    if !SENDER_NAME_PATTERN.isFullMatch(defaultSenderName) {
        return error InvalidSettingError(
                "The default sender name must be 1 to 11 alphanumeric characters, with no spaces or symbols.");
    }

    sns:Error? result = snsClient->setSMSAttributes({
        monthlySpendLimit,
        defaultSenderID: defaultSenderName
    });
    if result is sns:Error {
        return error("Unable to update account settings at this time. Please try again later.");
    }

    return {
        monthlySpendLimit,
        defaultSenderName
    };
}
