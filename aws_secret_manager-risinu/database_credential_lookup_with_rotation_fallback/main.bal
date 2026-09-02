import ballerina/http;

service /database on new http:Listener(servicePort) {

    # Returns the current database connection details (host, username,
    # password) pulled from the secret store.
    resource function get credentials() returns DatabaseCredentials|CredentialsNotFound|CredentialsUnavailable {
        return fetchDatabaseCredentials();
    }
}
