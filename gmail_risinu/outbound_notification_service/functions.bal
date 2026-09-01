import ballerina/lang.regexp;

final regexp:RegExp EMAIL_PATTERN = re `^[^@\s]+@[^@\s]+\.[^@\s]+$`;

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
