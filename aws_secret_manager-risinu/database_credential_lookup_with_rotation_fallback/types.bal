import ballerina/http;

# Database connection details as stored in the secret's JSON blob.
type DatabaseSecretPayload record {|
    string host;
    string username;
    string password;
|};

# Database connection details returned by the service.
public type DatabaseCredentials record {|
    string host;
    string username;
    string password;
|};

# Returned when the requested secret does not exist in the secret store,
# as opposed to a transient failure that may succeed on retry.
public type CredentialsNotFound record {|
    *http:NotFound;
    ErrorMessage body;
|};

# Returned for any other failure while retrieving or parsing the credentials.
# Never carries the underlying secret contents or stack trace.
public type CredentialsUnavailable record {|
    *http:ServiceUnavailable;
    ErrorMessage body;
|};

# A clean, generic error message safe to expose to callers.
public type ErrorMessage record {|
    string message;
|};
