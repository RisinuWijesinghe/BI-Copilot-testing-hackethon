// Request payload for sending a notification email.
type EmailNotificationRequest record {|
    string[] to;
    string subject;
    string htmlBody;
|};

// Successful response returned after the email has been accepted by Gmail.
type EmailNotificationResult record {|
    string notificationId;
|};

// Generic error body returned to callers. Never includes upstream error details,
// tokens, or client secrets.
type ErrorDetails record {|
    string message;
|};
