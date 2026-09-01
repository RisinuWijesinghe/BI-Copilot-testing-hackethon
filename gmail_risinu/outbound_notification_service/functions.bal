import ballerina/file;
import ballerina/lang.regexp;

final regexp:RegExp EMAIL_PATTERN = re `^[^@\s]+@[^@\s]+\.[^@\s]+$`;

// Checks that a caller-supplied file name is a plain name with no directory
// separators or parent-directory references, preventing path traversal outside
// the configured attachment base directory.
function isSafeFileName(string fileName) returns boolean {
    if fileName.trim().length() == 0 {
        return false;
    }
    if fileName.includes("/") || fileName.includes("\\") {
        return false;
    }
    if fileName == "." || fileName == ".." {
        return false;
    }
    return true;
}

// Validates the recipients list. Returns a field-specific error message when invalid, or () when valid.
function validateRecipients(string[] recipients) returns string? {
    if recipients.length() == 0 {
        return "recipients: at least one recipient email address is required";
    }
    foreach string recipient in recipients {
        if !EMAIL_PATTERN.isFullMatch(recipient) {
            return string `recipients: '${recipient}' is not a plausible email address`;
        }
    }
    return ();
}

// Validates the subject field. Returns a field-specific error message when invalid, or () when valid.
function validateSubject(string subject) returns string? {
    if subject.trim().length() == 0 {
        return "subject: subject must not be empty";
    }
    return ();
}

// Validates the HTML body field. Returns a field-specific error message when invalid, or () when valid.
function validateHtmlBody(string htmlBody) returns string? {
    if htmlBody.trim().length() == 0 {
        return "htmlBody: htmlBody must not be empty";
    }
    return ();
}

// Validates that a caller-supplied file name is a plain file name that exists under the
// configured attachment base directory and does not exceed the configured size limit.
// Returns a field-specific error message naming the offending file when validation fails,
// or () when the file is valid.
function validateAttachmentFile(string fieldName, string fileName) returns string? {
    if !isSafeFileName(fileName) {
        return string `${fieldName}: '${fileName}' is not a valid file name`;
    }

    string|file:Error resolvedPath = file:joinPath(attachmentBaseDirectory, fileName);
    if resolvedPath is file:Error {
        return string `${fieldName}: '${fileName}' is not a valid file name`;
    }

    boolean|file:Error exists = file:test(resolvedPath, file:EXISTS);
    if exists is file:Error || !exists {
        return string `${fieldName}: '${fileName}' does not exist`;
    }

    file:MetaData|file:Error metaData = file:getMetaData(resolvedPath);
    if metaData is file:Error {
        return string `${fieldName}: '${fileName}' could not be read`;
    }

    if metaData.size > maxAttachmentSizeBytes {
        return string `${fieldName}: '${fileName}' exceeds the maximum allowed size of ${maxAttachmentSizeBytes} bytes`;
    }

    return ();
}

// Determines the MIME type of a file from its extension. Falls back to a generic
// binary type when the extension is not recognized.
function guessMimeType(string fileName) returns string {
    string lowerCaseFileName = fileName.toLowerAscii();
    if lowerCaseFileName.endsWith(".pdf") {
        return "application/pdf";
    }
    if lowerCaseFileName.endsWith(".png") {
        return "image/png";
    }
    if lowerCaseFileName.endsWith(".jpg")||lowerCaseFileName.endsWith(".jpeg") {
        return "image/jpeg";
    }
    if lowerCaseFileName.endsWith(".gif") {
        return "image/gif";
    }
    if lowerCaseFileName.endsWith(".txt") {
        return "text/plain";
    }
    if lowerCaseFileName.endsWith(".csv") {
        return "text/csv";
    }
    if lowerCaseFileName.endsWith(".doc")||lowerCaseFileName.endsWith(".docx") {
        return "application/msword";
    }
    if lowerCaseFileName.endsWith(".xls")||lowerCaseFileName.endsWith(".xlsx") {
        return "application/vnd.ms-excel";
    }
    return "application/octet-stream";
}

// Checks whether the given recipient's domain is outside the configured internal domains.
function isExternalRecipient(string recipient) returns boolean {
    int? atIndex = recipient.lastIndexOf("@");
    if atIndex is () {
        return true;
    }
    string domain = recipient.substring(atIndex + 1).toLowerAscii();
    foreach string internalDomain in internalEmailDomains {
        if domain == internalDomain.toLowerAscii() {
            return false;
        }
    }
    return true;
}

// Determines whether any recipient of the notification is outside the company's
// configured internal email domains, meaning the notification requires review.
function requiresReview(string[] recipients) returns boolean {
    foreach string recipient in recipients {
        if isExternalRecipient(recipient) {
            return true;
        }
    }
    return false;
}
