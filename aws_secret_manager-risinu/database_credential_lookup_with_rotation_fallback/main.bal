import ballerina/http;

service /database on new http:Listener(servicePort) {

    # Returns the current database connection details (host, username,
    # password) pulled from the secret store. Only ever serves the current
    # secret version - if it is not available, fails loudly instead of
    # falling back to a previous version.
    resource function get credentials() returns DatabaseCredentials|CredentialsNotFound|CredentialsOutOfDate|CredentialsUnavailable {
        return fetchDatabaseCredentials();
    }
}
