import ballerina/http;
import ballerina/log;
import ballerinax/googleapis.gmail;

function init() returns error? {
    // Verify on startup that the mailbox is actually reachable so that a bad
    // credential surfaces immediately instead of on the first request.
    gmail:Profile|error profile = gmailClient->/users/me/profile();
    if profile is error {
        log:printError("failed to verify Gmail mailbox access on startup");
        return error("startup check failed: unable to reach the Gmail mailbox");
    }
    log:printInfo(string `Gmail mailbox verified, sending as: ${profile.emailAddress ?: "unknown"}`);
}

service /notifications on new http:Listener(servicePort) {

    # Sends a notification email through the team's Gmail account on behalf of an internal caller.
    #
    # + request - the recipients, subject and HTML body of the email to send
    # + return - the created notification identifier, a bad request when the payload is invalid,
    # or a generic failure when the email could not be sent
    resource function post email(EmailNotificationRequest request) returns EmailNotificationResult|http:BadRequest|http:InternalServerError {
        string? recipientsError = validateRecipients(request.to);
        if recipientsError is string {
            return <http:BadRequest>{body: {message: recipientsError}};
        }

        string? subjectError = validateSubject(request.subject);
        if subjectError is string {
            return <http:BadRequest>{body: {message: subjectError}};
        }

        string? htmlBodyError = validateHtmlBody(request.htmlBody);
        if htmlBodyError is string {
            return <http:BadRequest>{body: {message: htmlBodyError}};
        }

        gmail:MessageRequest gmailMessage = {
            to: request.to,
            subject: request.subject,
            bodyInHtml: request.htmlBody
        };

        gmail:Message|error sendResult = gmailClient->/users/me/messages/send.post(gmailMessage);
        if sendResult is error {
            log:printError("failed to send notification email via Gmail");
            return <http:InternalServerError>{body: {message: "couldn't send the notification email"}};
        }

        EmailNotificationResult result = {notificationId: sendResult.id};
        return result;
    }
}
