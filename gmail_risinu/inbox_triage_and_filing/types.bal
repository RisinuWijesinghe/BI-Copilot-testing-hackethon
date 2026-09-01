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

// The four filing categories. Every swept message is filed under exactly one of
// these; "EVERYTHING_ELSE" is the catch-all for messages that match no rule.
type Category "BILLING"|"BUGS"|"SALES"|"EVERYTHING_ELSE";

// The Gmail label name that a category is filed under.
type CategoryFolder record {|
    Category category;
    string labelName;
|};

// Keyword and sender-domain rule used to decide whether a message belongs to a
// given category. Matching is case-insensitive; either list may be empty.
type CategoryRule record {|
    Category category;
    string[] subjectKeywords;
    string[] senderDomains;
|};

// One filed message in a completed sweep: which category it landed in and its
// Gmail message identifier.
type FiledMessage record {|
    string messageId;
    Category category;
|};

// Result of a completed filing sweep.
type FilingSweepResult record {|
    FiledMessage[] filed;
|};

// Reported when a category folder could not be created, so filing was stopped
// before any message was touched.
type FilingSetupFailure record {|
    string message;
    Category category;
|};
