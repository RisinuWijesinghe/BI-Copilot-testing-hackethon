import ballerina/http;

# Request payload for updating account-wide SMS sending settings.
public type UpdateAccountSettingsRequest record {|
    int monthlySpendLimit;
    string defaultSenderName;
|};

# The account-wide SMS sending settings.
public type AccountSettings record {|
    int monthlySpendLimit;
    string defaultSenderName;
|};

# Response returned with the current account-wide SMS sending settings.
public type AccountSettingsRetrieved record {|
    *http:Ok;
    AccountSettings body;
|};

# Response returned when the account-wide SMS sending settings have been updated.
public type AccountSettingsUpdated record {|
    *http:Ok;
    AccountSettings body;
|};

# A clear, user-facing error body — never exposes internal error details.
public type ErrorDetails record {|
    string message;
|};

# Response returned when an invalid setting value is supplied.
public type InvalidSetting record {|
    *http:BadRequest;
    ErrorDetails body;
|};

# Response returned when the settings could not be read or updated.
public type ProcessingFailed record {|
    *http:InternalServerError;
    ErrorDetails body;
|};
