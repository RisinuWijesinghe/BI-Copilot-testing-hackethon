configurable string gmailClientId = ?;
configurable string gmailClientSecret = ?;
configurable string gmailRefreshToken = ?;
configurable string gmailRefreshUrl = "https://oauth2.googleapis.com/token";

configurable int servicePort = 8080;

// Directory on disk that attachments and inline images are resolved against.
// Callers reference files by name only; subdirectories are not allowed.
configurable string attachmentBaseDirectory = ?;

// Maximum allowed size, in bytes, for any single attached or inline file.
configurable int maxAttachmentSizeBytes = 10485760;

// Email domains considered internal to the company. A notification with at least
// one recipient outside these domains is parked for review instead of being sent
// immediately.
configurable string[] internalEmailDomains = ?;
