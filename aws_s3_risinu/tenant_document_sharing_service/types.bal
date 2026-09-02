# A short-lived download link for a document, safe to hand to a browser.
public type DownloadLink record {|
    string url;
    string expiresAt;
|};

# A short-lived upload link a browser can send a document's bytes to directly.
public type UploadLink record {|
    string url;
    string expiresAt;
|};

# A request to obtain a short-lived upload link for a named document.
public type UploadLinkRequest record {|
    string contentType;
    int expirationMinutes?;
|};

# Reports whether a document exists along with its size, type and last modified time.
public type DocumentStatus record {|
    boolean exists;
    int sizeInBytes;
    string contentType;
    string lastModified;
|};

# A generic, customer-safe error payload. Never includes AWS error codes, bucket names, or storage paths.
public type ErrorPayload record {|
    string message;
|};
