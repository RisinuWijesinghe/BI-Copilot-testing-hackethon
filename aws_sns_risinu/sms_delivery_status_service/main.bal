import ballerina/http;

listener http:Listener smsAdminListener = new (8080);

service /sms\-admin on smsAdminListener {

    # Reports the current account-wide SMS sending settings.
    #
    # + return - 200 OK with the current settings, or 500 if the settings could not be retrieved
    resource function get account\-settings() returns AccountSettingsRetrieved|ProcessingFailed {
        AccountSettings|error result = getAccountSettings();
        if result is error {
            return <ProcessingFailed>{
                body: {message: result.message()}
            };
        }
        return <AccountSettingsRetrieved>{
            body: result
        };
    }

    # Configures account-wide SMS sending settings, such as the monthly spending cap and the
    # default sender name used on outgoing messages. Intended for admin use.
    #
    # + request - the new settings to apply
    # + return - 200 OK with the updated settings, 400 if a supplied value is invalid, or 500 if the update failed
    resource function put account\-settings(@http:Payload UpdateAccountSettingsRequest request)
            returns AccountSettingsUpdated|InvalidSetting|ProcessingFailed {
        AccountSettings|InvalidSettingError|error result = updateAccountSettings(request);
        if result is InvalidSettingError {
            return <InvalidSetting>{
                body: {message: result.message()}
            };
        }
        if result is error {
            return <ProcessingFailed>{
                body: {message: result.message()}
            };
        }
        return <AccountSettingsUpdated>{
            body: result
        };
    }
}
