import ballerinax/aws.sns;

# Error raised when the given phone number is already registered in the SMS sandbox.
public type AlreadyRegisteredError distinct error;

# Error raised when confirmation is attempted with an incorrect one-time code.
public type IncorrectOtpError distinct error;

# Error raised when a message cannot be sent because the destination phone number has opted out of receiving messages.
public type RecipientOptedOutError distinct error;

# Registers a test phone number in the SMS sandbox and triggers a one-time code to be sent to it.
#
# + phoneNumber - the phone number to register
# + return - the registration result, an AlreadyRegisteredError if the number is already registered,
#            or a clear error if registration could not be completed
function registerTestPhoneNumber(string phoneNumber) returns RegistrationResult|AlreadyRegisteredError|error {
    sns:Error? result = snsClient->createSMSSandboxPhoneNumber(phoneNumber);
    if result is sns:Error {
        string errorMessage = result.message();
        if errorMessage.includes("AlreadyInSandboxException") || errorMessage.includes("already") {
            return error AlreadyRegisteredError("This phone number is already registered.");
        }
        return error("Unable to register this phone number at this time. Please try again later.");
    }

    return {
        phoneNumber,
        status: "registered, pending verification"
    };
}

# Confirms ownership of a test phone number using the one-time code sent to it.
#
# + phoneNumber - the phone number being confirmed
# + otp - the one-time code received on the phone
# + return - the confirmation result, an IncorrectOtpError if the code is wrong,
#            or a clear error if confirmation could not be completed
function confirmTestPhoneNumber(string phoneNumber, string otp) returns ConfirmationResult|IncorrectOtpError|error {
    sns:Error? result = snsClient->verifySMSSandboxPhoneNumber(phoneNumber, otp);
    if result is sns:Error {
        string errorMessage = result.message();
        if errorMessage.includes("VerificationException") || errorMessage.includes("verification code") {
            return error IncorrectOtpError("The one-time code provided is incorrect. Please check the code and try again.");
        }
        return error("Unable to confirm this phone number at this time. Please try again later.");
    }

    return {
        phoneNumber,
        status: "verified"
    };
}

# Sends a one-off text message to a confirmed test phone number, refusing to send if the
# number has opted out of receiving messages.
#
# + phoneNumber - the confirmed test phone number to send the message to
# + message - the message text to send
# + return - the send result, a RecipientOptedOutError if the number has opted out,
#            or a clear error if the message could not be sent
function sendTestMessage(string phoneNumber, string message) returns MessageSendResult|RecipientOptedOutError|error {
    boolean|sns:Error optedOut = snsClient->checkIfPhoneNumberIsOptedOut(phoneNumber);
    if optedOut is sns:Error {
        return error("Unable to check the opt-out status of this phone number at this time. Please try again later.");
    }
    if optedOut {
        return error RecipientOptedOutError("This phone number has opted out of receiving messages and cannot be sent to.");
    }

    sns:PublishMessageResponse|sns:Error response = snsClient->publish(phoneNumber, message);
    if response is sns:Error {
        return error("Unable to send this message at this time. Please try again later.");
    }

    return {
        phoneNumber,
        messageId: response.messageId,
        status: "message sent"
    };
}

# Removes a test phone number from the SMS sandbox that is no longer needed.
#
# + phoneNumber - the test phone number to remove
# + return - true once removed, or a clear error if removal failed
function removeTestPhoneNumber(string phoneNumber) returns boolean|error {
    sns:Error? result = snsClient->deleteSMSSandboxPhoneNumber(phoneNumber);
    if result is sns:Error {
        return error("Unable to remove this phone number at this time. Please try again later.");
    }
    return true;
}

# Lists the test phone numbers currently registered in the SMS sandbox.
#
# + return - the list of current test phone numbers, or a clear error if the list could not be retrieved
function listTestPhoneNumbers() returns TestPhoneNumber[]|error {
    stream<sns:SMSSandboxPhoneNumber, sns:Error?> sandboxNumbers = snsClient->listSMSSandboxPhoneNumbers();

    TestPhoneNumber[] testPhoneNumbers = [];
    error? iterationResult = sandboxNumbers.forEach(function(sns:SMSSandboxPhoneNumber sandboxNumber) {
        testPhoneNumbers.push({
            phoneNumber: sandboxNumber.phoneNumber,
            status: sandboxNumber.status
        });
    });
    if iterationResult is error {
        return error("Unable to list test phone numbers at this time. Please try again later.");
    }

    return testPhoneNumbers;
}
