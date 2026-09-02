import ballerina/http;

listener http:Listener matchDayListener = new (8080);

service /match\-alerts on matchDayListener {

    # Signs a fan up to receive future match alerts.
    #
    # + request - the subscription request containing the fan's email address
    # + return - 202 Accepted on success, 400 for an unusable email, or 500 if the subscription failed
    resource function post subscribers(@http:Payload SubscriptionRequest request)
            returns SubscriptionAccepted|InvalidRequest|ProcessingFailed {
        string email = request.email;
        if !isValidEmail(email) {
            return <InvalidRequest>{
                body: {message: "The provided email address is not valid. Please provide a usable email address."}
            };
        }

        SubscriptionResult|error result = subscribeFanToMatchAlerts(email);
        if result is error {
            return <ProcessingFailed>{
                body: {message: result.message()}
            };
        }
        return <SubscriptionAccepted>{
            body: result
        };
    }

    # Sends a match alert to everyone currently subscribed. Intended for admin use.
    #
    # + request - the alert request containing the message text to broadcast
    # + return - 200 OK on success, 400 if the message text is missing, or 500 if the alert could not be sent
    resource function post alerts(@http:Payload AlertRequest request)
            returns AlertSent|InvalidRequest|ProcessingFailed {
        string message = request.message.trim();
        if message.length() == 0 {
            return <InvalidRequest>{
                body: {message: "Alert message text must not be empty."}
            };
        }

        AlertResult|error result = broadcastMatchAlert(message);
        if result is error {
            return <ProcessingFailed>{
                body: {message: result.message()}
            };
        }
        return <AlertSent>{
            body: result
        };
    }
}
