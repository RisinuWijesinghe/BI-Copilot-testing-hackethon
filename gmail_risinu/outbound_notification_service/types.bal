// Reference to a document to attach, resolved by filename against the configured
// attachment base directory.
type AttachmentReference record {|
    string fileName;
|};

// Reference to an image that should render inline in the HTML body (e.g. a logo),
// resolved by filename against the configured attachment base directory.
type InlineImageReference record {|
    string fileName;
    string contentId;
|};

// Request payload for sending a notification email.
type EmailNotificationRequest record {|
    string[] to;
    string subject;
    string htmlBody;
    AttachmentReference[] attachments = [];
    InlineImageReference[] inlineImages = [];
|};

// Successful response returned after the email has been accepted by Gmail, or after
// a notification requiring review has been parked awaiting approval.
type EmailNotificationResult record {|
    string notificationId;
    NotificationStatus status;
|};

// Generic error body returned to callers. Never includes upstream error details,
// tokens, or client secrets.
type ErrorDetails record {|
    string message;
|};

// Lifecycle status of a notification that required review before sending.
type NotificationStatus "PARKED"|"SENT";

// Internal record representing a notification, whether parked awaiting review or already sent.
type StoredNotification record {|
    string notificationId;
    string[] to;
    string subject;
    string htmlBody;
    AttachmentReference[] attachments;
    InlineImageReference[] inlineImages;
    NotificationStatus status;
    string createdAt;
|};

// Summary view of a parked notification, returned when listing parked notifications.
type ParkedNotificationSummary record {|
    string notificationId;
    string[] to;
    string subject;
    string createdAt;
|};

// Detailed view of a parked notification, returned when looking at one in detail.
type ParkedNotificationDetail record {|
    string notificationId;
    string[] to;
    string subject;
    string htmlBody;
    AttachmentReference[] attachments;
    InlineImageReference[] inlineImages;
    string createdAt;
|};

// Response returned once a parked notification has been approved and sent.
type ApprovalResult record {|
    string notificationId;
|};

// Request payload for revising a parked notification. Replaces the recipients,
// subject and body while keeping the same notification identifier.
type EmailNotificationRevision record {|
    string[] to;
    string subject;
    string htmlBody;
    AttachmentReference[] attachments = [];
    InlineImageReference[] inlineImages = [];
|};

// Counts of notifications tracked by the service since startup.
type NotificationStats record {|
    int parkedCount;
    int sentCount;
    int discardedCount;
|};
