import ballerinax/aws.sns;

# Error raised when the given phone number is already registered in the SMS sandbox.
public type AlreadyRegisteredError distinct error;

# Error raised when confirmation is attempted with an incorrect one-time code.
public type IncorrectOtpError distinct error;

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
