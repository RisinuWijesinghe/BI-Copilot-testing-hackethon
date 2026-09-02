import ballerina/http;

listener http:Listener matchDayListener = new (8080);

service /match\-alerts on matchDayListener {

    # Signs a fan up to receive future match alerts.
    #
    # + request - the subscription request containing the fan's email address and alert preference
    # + return - 202 Accepted on success, 400 for an unusable email, or 500 if the subscription failed
    resource function post subscribers(@http:Payload SubscriptionRequest request)
            returns SubscriptionAccepted|InvalidRequest|ProcessingFailed {
        string email = request.email;
        if !isValidEmail(email) {
            return <InvalidRequest>{
                body: {message: "The provided email address is not valid. Please provide a usable email address."}
            };
        }

        SubscriptionResult|error result = subscribeFanToMatchAlerts(email, request.preference);
        if result is error {
            return <ProcessingFailed>{
                body: {message: result.message()}
            };
        }
        return <SubscriptionAccepted>{
            body: result
        };
    }

    # Lists everyone currently signed up to receive match alerts.
    #
    # + return - 200 OK with the current list of subscribers
    resource function get subscribers() returns SubscriberList {
        return <SubscriberList>{
            body: listCurrentSubscribers()
        };
    }

    # Unsubscribes a fan using the identifier they were given when they signed up.
    #
    # + subscriberId - the identifier returned at signup time
    # + return - 200 OK on success, 404 if the identifier is unknown, or 500 if the removal failed
    resource function delete subscribers/[string subscriberId]()
            returns UnsubscribeConfirmed|SubscriberNotFound|ProcessingFailed {
        boolean|error result = unsubscribeFan(subscriberId);
        if result is error {
            return <ProcessingFailed>{
                body: {message: result.message()}
            };
        }
        if !result {
            return <SubscriberNotFound>{
                body: {message: "No subscriber found for the given identifier."}
            };
        }
        return <UnsubscribeConfirmed>{
            body: {status: "unsubscribed"}
        };
    }

    # Sends a match alert to everyone currently subscribed to that kind of update. Intended for admin use.
    #
    # + request - the alert request containing the event type and message text to broadcast
    # + return - 200 OK on success, 400 if the message text is missing, or 500 if the alert could not be sent
    resource function post alerts(@http:Payload AlertRequest request)
            returns AlertSent|InvalidRequest|ProcessingFailed {
        string message = request.message.trim();
        if message.length() == 0 {
            return <InvalidRequest>{
                body: {message: "Alert message text must not be empty."}
            };
        }

        AlertResult|error result = broadcastMatchAlert(request.eventType, message);
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
