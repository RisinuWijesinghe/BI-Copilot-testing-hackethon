import ballerina/http;

# Request payload for registering a test phone number.
public type RegisterTestNumberRequest record {|
    string phoneNumber;
|};

# Request payload for confirming ownership of a test phone number using the one-time code sent to it.
public type ConfirmTestNumberRequest record {|
    string otp;
|};

# A test phone number as tracked in the SMS sandbox.
public type TestPhoneNumber record {|
    string phoneNumber;
    string status;
|};

# Body of a successful registration response.
public type RegistrationResult record {|
    string phoneNumber;
    string status;
|};

# Body of a successful confirmation response.
public type ConfirmationResult record {|
    string phoneNumber;
    string status;
|};

# Response returned when a test phone number has been registered and an OTP has been sent to it.
public type RegistrationAccepted record {|
    *http:Accepted;
    RegistrationResult body;
|};

# Response returned when a test phone number has been successfully verified.
public type ConfirmationSucceeded record {|
    *http:Ok;
    ConfirmationResult body;
|};

# Response returned with the list of currently registered test phone numbers.
public type TestPhoneNumberList record {|
    *http:Ok;
    TestPhoneNumber[] body;
|};

# A clear, user-facing error body — never exposes internal error details.
public type ErrorDetails record {|
    string message;
|};

# Response returned when a request fails validation (e.g. an unusable phone number).
public type InvalidRequest record {|
    *http:BadRequest;
    ErrorDetails body;
|};

# Response returned when confirmation is attempted with an incorrect one-time code.
public type IncorrectOtp record {|
    *http:BadRequest;
    ErrorDetails body;
|};

# Response returned when the phone number is already registered.
public type AlreadyRegistered record {|
    *http:Conflict;
    ErrorDetails body;
|};

# Response returned when the referenced test phone number cannot be found.
public type TestNumberNotFound record {|
    *http:NotFound;
    ErrorDetails body;
|};

# Response returned when the registration, confirmation, or listing could not be processed.
public type ProcessingFailed record {|
    *http:InternalServerError;
    ErrorDetails body;
|};
