import ballerina/http;

listener http:Listener smsTestListener = new (8080);

service /sms\-test on smsTestListener {

    # Registers a test phone number and triggers a one-time code to be sent to it.
    #
    # + request - the registration request containing the phone number to register
    # + return - 202 Accepted on success, 409 if the number is already registered, or 500 if registration failed
    resource function post test\-numbers(@http:Payload RegisterTestNumberRequest request)
            returns RegistrationAccepted|AlreadyRegistered|ProcessingFailed {
        string phoneNumber = request.phoneNumber;

        RegistrationResult|AlreadyRegisteredError|error result = registerTestPhoneNumber(phoneNumber);
        if result is AlreadyRegisteredError {
            return <AlreadyRegistered>{
                body: {message: result.message()}
            };
        }
        if result is error {
            return <ProcessingFailed>{
                body: {message: result.message()}
            };
        }
        return <RegistrationAccepted>{
            body: result
        };
    }

    # Confirms ownership of a test phone number using the one-time code sent to it.
    #
    # + phoneNumber - the phone number being confirmed
    # + request - the confirmation request containing the one-time code
    # + return - 200 OK on success, 400 if the code is incorrect, or 500 if confirmation failed
    resource function post test\-numbers/[string phoneNumber]/verify(@http:Payload ConfirmTestNumberRequest request)
            returns ConfirmationSucceeded|IncorrectOtp|ProcessingFailed {
        string otp = request.otp;

        ConfirmationResult|IncorrectOtpError|error result = confirmTestPhoneNumber(phoneNumber, otp);
        if result is IncorrectOtpError {
            return <IncorrectOtp>{
                body: {message: result.message()}
            };
        }
        if result is error {
            return <ProcessingFailed>{
                body: {message: result.message()}
            };
        }
        return <ConfirmationSucceeded>{
            body: result
        };
    }

    # Lists the test phone numbers currently registered.
    #
    # + return - 200 OK with the current list of test phone numbers, or 500 if the list could not be retrieved
    resource function get test\-numbers() returns TestPhoneNumberList|ProcessingFailed {
        TestPhoneNumber[]|error result = listTestPhoneNumbers();
        if result is error {
            return <ProcessingFailed>{
                body: {message: result.message()}
            };
        }
        return <TestPhoneNumberList>{
            body: result
        };
    }

    # Sends a one-off text message to a confirmed test phone number. Refuses to send, with a
    # clear reason, if the number has opted out of receiving messages.
    #
    # + phoneNumber - the confirmed test phone number to send the message to
    # + request - the send request containing the message text
    # + return - 200 OK on success, 403 if the number has opted out, or 500 if the message could not be sent
    resource function post test\-numbers/[string phoneNumber]/messages(@http:Payload SendTestMessageRequest request)
            returns MessageSent|RecipientOptedOut|ProcessingFailed {
        string message = request.message;

        MessageSendResult|RecipientOptedOutError|error result = sendTestMessage(phoneNumber, message);
        if result is RecipientOptedOutError {
            return <RecipientOptedOut>{
                body: {message: result.message()}
            };
        }
        if result is error {
            return <ProcessingFailed>{
                body: {message: result.message()}
            };
        }
        return <MessageSent>{
            body: result
        };
    }

    # Removes a test phone number that is no longer needed.
    #
    # + phoneNumber - the test phone number to remove
    # + return - 200 OK on success, or 500 if the removal failed
    resource function delete test\-numbers/[string phoneNumber]() returns TestNumberRemoved|ProcessingFailed {
        boolean|error result = removeTestPhoneNumber(phoneNumber);
        if result is error {
            return <ProcessingFailed>{
                body: {message: result.message()}
            };
        }
        return <TestNumberRemoved>{
            body: {status: "removed"}
        };
    }
}
