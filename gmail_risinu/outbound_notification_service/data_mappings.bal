import ballerina/file;
import ballerinax/googleapis.gmail;

// Builds the Gmail send request from a stored notification, resolving each attachment
// and inline image reference to its absolute path under the attachment base directory.
function toGmailMessageRequest(StoredNotification notification) returns gmail:MessageRequest|error {
    gmail:AttachmentFile[] attachmentFiles = [];
    foreach AttachmentReference attachment in notification.attachments {
        string resolvedPath = check file:joinPath(attachmentBaseDirectory, attachment.fileName);
        attachmentFiles.push({
            name: attachment.fileName,
            mimeType: guessMimeType(attachment.fileName),
            path: resolvedPath
        });
    }

    gmail:ImageFile[] inlineImageFiles = [];
    foreach InlineImageReference inlineImage in notification.inlineImages {
        string resolvedPath = check file:joinPath(attachmentBaseDirectory, inlineImage.fileName);
        inlineImageFiles.push({
            contentId: inlineImage.contentId,
            name: inlineImage.fileName,
            mimeType: guessMimeType(inlineImage.fileName),
            path: resolvedPath
        });
    }

    gmail:MessageRequest gmailMessage = {
        to: notification.to,
        subject: notification.subject,
        bodyInHtml: notification.htmlBody,
        attachments: attachmentFiles,
        inlineImages: inlineImageFiles
    };
    return gmailMessage;
}
