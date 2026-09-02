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

    # Sends a batch of distinct match alerts to everyone currently subscribed, in a single call.
    # Intended for admin use.
    #
    # + request - the alert batch request containing the alerts to broadcast
    # + return - 200 OK with the per-alert outcomes, 400 if the batch is empty or an alert has no text, or 500 if the batch could not be sent
    resource function post alerts(@http:Payload AlertBatchRequest request)
            returns AlertBatchSent|InvalidRequest|ProcessingFailed {
        AlertItem[] alerts = request.alerts;
        if alerts.length() == 0 {
            return <InvalidRequest>{
                body: {message: "At least one alert must be provided."}
            };
        }
        foreach AlertItem alertItem in alerts {
            string trimmedMessage = alertItem.message.trim();
            if trimmedMessage.length() == 0 {
                return <InvalidRequest>{
                    body: {message: "Each alert must have non-empty message text."}
                };
            }
        }

        AlertOutcome[]|error result = broadcastMatchAlerts(alerts);
        if result is error {
            return <ProcessingFailed>{
                body: {message: result.message()}
            };
        }
        return <AlertBatchSent>{
            body: {results: result}
        };
    }
}
