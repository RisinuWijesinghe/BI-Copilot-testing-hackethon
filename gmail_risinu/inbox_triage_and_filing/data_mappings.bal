import ballerinax/googleapis.gmail;

// Builds a triage entry from a Gmail message fetched with metadata format. Only the
// snippet is used for the preview so the full message body is never touched.
function toUnreadMessageEntry(gmail:Message message) returns UnreadMessageEntry => {
    'from: extractHeaderValue(message, "From"),
    subject: extractHeaderValue(message, "Subject"),
    receivedAt: extractHeaderValue(message, "Date"),
    preview: toOneLinePreview(message.snippet ?: "")
};

// Reads a header value from the message payload's header map, falling back to an
// empty string when the header is absent.
function extractHeaderValue(gmail:Message message, string headerName) returns string {
    gmail:MessagePart? payload = message.payload;
    if payload is () {
        return "";
    }
    map<string>? headers = payload.headers;
    if headers is () {
        return "";
    }
    return headers[headerName] ?: "";
}

// Collapses the snippet into a single line, since Gmail's snippet is already a
// short plain-text preview but may still contain stray line breaks.
function toOneLinePreview(string snippet) returns string {
    string withoutNewlines = re `[\r\n]+`.replaceAll(snippet, " ");
    return withoutNewlines.trim();
}
