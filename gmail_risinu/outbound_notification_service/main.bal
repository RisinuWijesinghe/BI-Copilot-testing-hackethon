import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;
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
    # Notifications with a recipient outside the company's internal domains are parked for
    # review instead of being sent immediately.
    #
    # + request - the recipients, subject, HTML body, and optional attachments/inline images
    # + return - the created notification identifier and its status, a bad request when the
    # payload or a referenced file is invalid, or a generic failure when the email could not be sent
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

        foreach AttachmentReference attachment in request.attachments {
            string? attachmentError = validateAttachmentFile("attachments", attachment.fileName);
            if attachmentError is string {
                return <http:BadRequest>{body: {message: attachmentError}};
            }
        }

        foreach InlineImageReference inlineImage in request.inlineImages {
            string? inlineImageError = validateAttachmentFile("inlineImages", inlineImage.fileName);
            if inlineImageError is string {
                return <http:BadRequest>{body: {message: inlineImageError}};
            }
        }

        string notificationId = uuid:createType4AsString();
        string createdAt = time:utcToString(time:utcNow());

        StoredNotification notification = {
            notificationId,
            to: request.to,
            subject: request.subject,
            htmlBody: request.htmlBody,
            attachments: request.attachments,
            inlineImages: request.inlineImages,
            status: "PARKED",
            createdAt
        };

        if requiresReview(request.to) {
            storeNotification(notification);
            log:printInfo(string `notification ${notificationId} parked for review, has external recipients`);
            return {notificationId, status: "PARKED"};
        }

        gmail:Message|error sendResult = sendNotification(notification);
        if sendResult is error {
            log:printError("failed to send notification email via Gmail");
            return <http:InternalServerError>{body: {message: "couldn't send the notification email"}};
        }

        notification.status = "SENT";
        storeNotification(notification);
        markSent();
        return {notificationId, status: "SENT"};
    }

    # Lists notifications currently parked awaiting review.
    #
    # + return - the summaries of all parked notifications
    resource function get parked() returns ParkedNotificationSummary[] {
        StoredNotification[] parkedNotifications = listParkedNotifications();
        return from StoredNotification notification in parkedNotifications
            select {
                notificationId: notification.notificationId,
                to: notification.to,
                subject: notification.subject,
                createdAt: notification.createdAt
            };
    }

    # Looks at a single parked notification in detail.
    #
    # + notificationId - the identifier of the parked notification
    # + return - the full detail of the parked notification, or not found when it does not exist or is not parked
    resource function get parked/[string notificationId]() returns ParkedNotificationDetail|http:NotFound {
        StoredNotification? notification = getNotification(notificationId);
        if notification is () || notification.status != "PARKED" {
            return <http:NotFound>{body: {message: "no parked notification found for the given identifier"}};
        }

        return {
            notificationId: notification.notificationId,
            to: notification.to,
            subject: notification.subject,
            htmlBody: notification.htmlBody,
            attachments: notification.attachments,
            inlineImages: notification.inlineImages,
            createdAt: notification.createdAt
        };
    }

    # Approves a parked notification, which sends it through Gmail.
    #
    # + notificationId - the identifier of the parked notification to approve
    # + return - the sent notification identifier, not found when it was already sent or never existed,
    # or a generic failure when the email could not be sent
    resource function post parked/[string notificationId]/approve() returns ApprovalResult|http:NotFound|http:InternalServerError {
        StoredNotification? notification = getNotification(notificationId);
        if notification is () || notification.status != "PARKED" {
            return <http:NotFound>{body: {message: "no parked notification found for the given identifier"}};
        }

        gmail:Message|error sendResult = sendNotification(notification);
        if sendResult is error {
            log:printError("failed to send approved notification email via Gmail");
            return <http:InternalServerError>{body: {message: "couldn't send the notification email"}};
        }

        notification.status = "SENT";
        storeNotification(notification);
        markSent();
        return {notificationId: notification.notificationId};
    }

    # Revises a parked notification's recipients, subject or body ahead of approval.
    # The notification identifier is preserved so callers tracking it do not lose it.
    #
    # + notificationId - the identifier of the parked notification to revise
    # + revision - the replacement recipients, subject, HTML body, and optional attachments/inline images
    # + return - the updated parked notification detail, not found when it does not exist or is not parked,
    # or a bad request when the revised payload or a referenced file is invalid
    resource function put parked/[string notificationId](EmailNotificationRevision revision) returns ParkedNotificationDetail|http:NotFound|http:BadRequest {
        StoredNotification? existingNotification = getNotification(notificationId);
        if existingNotification is () || existingNotification.status != "PARKED" {
            return <http:NotFound>{body: {message: "no parked notification found for the given identifier"}};
        }

        string? recipientsError = validateRecipients(revision.to);
        if recipientsError is string {
            return <http:BadRequest>{body: {message: recipientsError}};
        }

        string? subjectError = validateSubject(revision.subject);
        if subjectError is string {
            return <http:BadRequest>{body: {message: subjectError}};
        }

        string? htmlBodyError = validateHtmlBody(revision.htmlBody);
        if htmlBodyError is string {
            return <http:BadRequest>{body: {message: htmlBodyError}};
        }

        foreach AttachmentReference attachment in revision.attachments {
            string? attachmentError = validateAttachmentFile("attachments", attachment.fileName);
            if attachmentError is string {
                return <http:BadRequest>{body: {message: attachmentError}};
            }
        }

        foreach InlineImageReference inlineImage in revision.inlineImages {
            string? inlineImageError = validateAttachmentFile("inlineImages", inlineImage.fileName);
            if inlineImageError is string {
                return <http:BadRequest>{body: {message: inlineImageError}};
            }
        }

        StoredNotification revisedNotification = {
            notificationId,
            to: revision.to,
            subject: revision.subject,
            htmlBody: revision.htmlBody,
            attachments: revision.attachments,
            inlineImages: revision.inlineImages,
            status: "PARKED",
            createdAt: existingNotification.createdAt
        };
        storeNotification(revisedNotification);

        return {
            notificationId: revisedNotification.notificationId,
            to: revisedNotification.to,
            subject: revisedNotification.subject,
            htmlBody: revisedNotification.htmlBody,
            attachments: revisedNotification.attachments,
            inlineImages: revisedNotification.inlineImages,
            createdAt: revisedNotification.createdAt
        };
    }

    # Discards a parked notification. The notification is removed entirely rather
    # than being hidden or marked in any way.
    #
    # + notificationId - the identifier of the parked notification to discard
    # + return - no content on success, or not found when it does not exist or is not parked
    resource function delete parked/[string notificationId]() returns http:NoContent|http:NotFound {
        StoredNotification? existingNotification = getNotification(notificationId);
        if existingNotification is () || existingNotification.status != "PARKED" {
            return <http:NotFound>{body: {message: "no parked notification found for the given identifier"}};
        }

        removeNotification(notificationId);
        markDiscarded();
        return http:NO_CONTENT;
    }

    # Reports how many notifications are currently parked, how many have been sent,
    # and how many have been discarded since startup.
    #
    # + return - the current notification counts
    resource function get stats() returns NotificationStats {
        return currentStats();
    }
}

// Builds the Gmail request from the stored notification and sends it, returning the
// upstream error unchanged so the caller can log context without exposing it.
function sendNotification(StoredNotification notification) returns gmail:Message|error {
    gmail:MessageRequest gmailMessage = check toGmailMessageRequest(notification);
    return gmailClient->/users/me/messages/send.post(gmailMessage);
}
