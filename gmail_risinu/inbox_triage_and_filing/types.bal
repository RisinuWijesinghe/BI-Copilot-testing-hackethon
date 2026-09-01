// One triaged entry in the unread-mail sweep. Only a short preview of the message
// is ever exposed here — never the full body — since this is rendered on a
// dashboard that is not cleared for message content.
type UnreadMessageEntry record {|
    string 'from;
    string subject;
    string receivedAt;
    string preview;
|};

// Generic failure returned to callers. Never includes upstream Gmail error
// details, tokens, or credentials.
type ErrorDetails record {|
    string message;
|};
