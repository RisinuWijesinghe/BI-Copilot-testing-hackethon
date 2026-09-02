import ballerina/test;
import ballerinax/aws.sns;

// ---- Reading account settings ----

@test:Config {}
function testGetAccountSettingsSuccess() returns error? {
    test:MockObject mockSns = test:prepare(snsClient);
    sns:SMSAttributes attributes = {
        monthlySpendLimit: 250,
        defaultSenderID: "ACMECORP"
    };
    mockSns.when("getSMSAttributes").thenReturn(attributes);
    snsClient = <sns:Client>mockSns;

    AccountSettings result = check getAccountSettings();

    test:assertEquals(result.monthlySpendLimit, 250, msg = "unexpected monthly spend limit");
    test:assertEquals(result.defaultSenderName, "ACMECORP", msg = "unexpected default sender name");
}

@test:Config {}
function testGetAccountSettingsSnsFailureReturnsCleanError() {
    test:MockObject mockSns = test:prepare(snsClient);
    sns:Error snsError = error sns:Error("internal aws failure: access denied");
    mockSns.when("getSMSAttributes").thenReturn(snsError);
    snsClient = <sns:Client>mockSns;

    AccountSettings|error result = getAccountSettings();

    test:assertTrue(result is error, "expected an error when SNS getSMSAttributes fails");
    if result is error {
        string errorMessage = result.message();
        test:assertEquals(errorMessage, "Unable to retrieve account settings at this time. Please try again later.",
                msg = "error message should be a clean, generic failure and not leak AWS details");
    }
}

// ---- Updating account settings ----

@test:Config {}
function testUpdateAccountSettingsSuccess() returns error? {
    test:MockObject mockSns = test:prepare(snsClient);
    mockSns.when("setSMSAttributes").thenReturn(());
    snsClient = <sns:Client>mockSns;

    UpdateAccountSettingsRequest request = {
        monthlySpendLimit: 500,
        defaultSenderName: "ACMECORP"
    };
    AccountSettings result = check updateAccountSettings(request);

    test:assertEquals(result.monthlySpendLimit, 500, msg = "unexpected monthly spend limit in response");
    test:assertEquals(result.defaultSenderName, "ACMECORP", msg = "unexpected default sender name in response");
}

@test:Config {}
function testUpdateAccountSettingsSnsFailureReturnsCleanError() {
    test:MockObject mockSns = test:prepare(snsClient);
    sns:Error snsError = error sns:Error("internal aws failure: throttled");
    mockSns.when("setSMSAttributes").thenReturn(snsError);
    snsClient = <sns:Client>mockSns;

    UpdateAccountSettingsRequest request = {
        monthlySpendLimit: 500,
        defaultSenderName: "ACMECORP"
    };
    AccountSettings|InvalidSettingError|error result = updateAccountSettings(request);

    test:assertTrue(result is error, "expected an error when SNS setSMSAttributes fails");
    if result is error {
        string errorMessage = result.message();
        test:assertEquals(errorMessage, "Unable to update account settings at this time. Please try again later.",
                msg = "error message should be a clean, generic failure and not leak AWS details");
    }
}

// ---- Invalid settings ----

@test:Config {}
function testUpdateAccountSettingsRejectsNonPositiveSpendLimit() {
    UpdateAccountSettingsRequest request = {
        monthlySpendLimit: 0,
        defaultSenderName: "ACMECORP"
    };
    AccountSettings|InvalidSettingError|error result = updateAccountSettings(request);

    test:assertTrue(result is InvalidSettingError, "expected a non-positive spend limit to be rejected as invalid");
    if result is InvalidSettingError {
        test:assertEquals(result.message(), "The monthly spend limit must be a positive amount.",
                msg = "unexpected error message for a non-positive spend limit");
    }
}

@test:Config {}
function testUpdateAccountSettingsRejectsUnusableSenderName() {
    UpdateAccountSettingsRequest request = {
        monthlySpendLimit: 500,
        defaultSenderName: "This Is Way Too Long"
    };
    AccountSettings|InvalidSettingError|error result = updateAccountSettings(request);

    test:assertTrue(result is InvalidSettingError, "expected an unusable sender name to be rejected as invalid");
    if result is InvalidSettingError {
        test:assertEquals(result.message(),
                "The default sender name must be 1 to 11 alphanumeric characters, with no spaces or symbols.",
                msg = "unexpected error message for an unusable sender name");
    }
}
