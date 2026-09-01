import ballerinax/googleapis.gmail;

// The four category folders, in the fixed order that categories are evaluated in:
// the first matching rule wins, and "everything-else" is always the catch-all.
final CategoryFolder[] CATEGORY_FOLDERS = [
    {category: "BILLING", labelName: "billing"},
    {category: "BUGS", labelName: "bugs"},
    {category: "SALES", labelName: "sales"},
    {category: "EVERYTHING_ELSE", labelName: "everything-else"}
];

// Splits a comma-separated configuration value into a trimmed, lower-cased list,
// dropping any blank entries left by stray commas or empty configuration.
function splitConfigList(string configValue) returns string[] {
    string[] rawParts = re `,`.split(configValue);
    string[] parts = [];
    foreach string rawPart in rawParts {
        string trimmedPart = rawPart.trim().toLowerAscii();
        if trimmedPart.length() > 0 {
            parts.push(trimmedPart);
        }
    }
    return parts;
}

// Builds the ordered category rules from configuration. "EVERYTHING_ELSE" carries
// no rule of its own since it is the catch-all for anything that matches nothing else.
function buildCategoryRules() returns CategoryRule[] {
    return [
        {
            category: "BILLING",
            subjectKeywords: splitConfigList(billingSubjectKeywords),
            senderDomains: splitConfigList(billingSenderDomains)
        },
        {
            category: "BUGS",
            subjectKeywords: splitConfigList(bugsSubjectKeywords),
            senderDomains: splitConfigList(bugsSenderDomains)
        },
        {
            category: "SALES",
            subjectKeywords: splitConfigList(salesSubjectKeywords),
            senderDomains: splitConfigList(salesSenderDomains)
        }
    ];
}

// Extracts the domain portion of a sender header value, which may be a plain
// address or a "Display Name <address@domain>" form.
function extractSenderDomain(string sender) returns string {
    string addressPart = sender;
    int? openAngle = sender.lastIndexOf("<");
    int? closeAngle = sender.lastIndexOf(">");
    if openAngle is int && closeAngle is int && closeAngle > openAngle {
        addressPart = sender.substring(openAngle + 1, closeAngle);
    }
    int? atIndex = addressPart.lastIndexOf("@");
    if atIndex is () {
        return "";
    }
    return addressPart.substring(atIndex + 1).trim().toLowerAscii();
}

// Decides whether a message matches a single category rule: either its subject
// contains one of the rule's keywords, or its sender's domain is one of the rule's domains.
function matchesCategoryRule(CategoryRule rule, string subject, string sender) returns boolean {
    string lowerCaseSubject = subject.toLowerAscii();
    foreach string keyword in rule.subjectKeywords {
        if lowerCaseSubject.includes(keyword) {
            return true;
        }
    }
    string senderDomain = extractSenderDomain(sender);
    if senderDomain.length() > 0 {
        foreach string domain in rule.senderDomains {
            if senderDomain == domain {
                return true;
            }
        }
    }
    return false;
}

// Classifies a message into one of the four categories using the configured rules,
// in order, falling back to the "everything-else" catch-all when nothing matches.
function classifyMessage(string subject, string sender) returns Category {
    CategoryRule[] rules = buildCategoryRules();
    foreach CategoryRule rule in rules {
        if matchesCategoryRule(rule, subject, sender) {
            return rule.category;
        }
    }
    return "EVERYTHING_ELSE";
}

// Builds the Gmail search query for the unread sweep: always restricted to unread
// mail in the inbox, optionally narrowed further by a caller-supplied search phrase.
function buildUnreadQuery(string? searchPhrase) returns string {
    if searchPhrase is string && searchPhrase.trim().length() > 0 {
        return string `label:INBOX is:unread ${searchPhrase}`;
    }
    return "label:INBOX is:unread";
}

// Sweeps unread mail in the inbox, optionally narrowed by a search phrase, and
// returns one triaged entry per message. Any failure to reach the mailbox or a
// rejected credential is collapsed into a single generic error so that nothing
// from Gmail's own error surface ever reaches the caller.
function sweepUnreadMessages(string? searchPhrase) returns UnreadMessageEntry[]|error {
    string query = buildUnreadQuery(searchPhrase);

    gmail:ListMessagesResponse|error listResult = gmailClient->/users/me/messages(q = query);
    if listResult is error {
        return error("triage is unavailable");
    }

    gmail:Message[]? messageRefs = listResult.messages;
    if messageRefs is () {
        return [];
    }

    UnreadMessageEntry[] entries = [];
    foreach gmail:Message messageRef in messageRefs {
        gmail:Message|error fullMessage = gmailClient->/users/me/messages/[messageRef.id](
            format = "metadata",
            metadataHeaders = ["From", "Subject", "Date"]
        );
        if fullMessage is error {
            return error("triage is unavailable");
        }
        entries.push(toUnreadMessageEntry(fullMessage));
    }

    return entries;
}

// Fetches all labels currently in the mailbox as a map keyed by (lower-cased)
// label name, so lookups for the four category folders are case-insensitive.
function fetchLabelsByName() returns map<gmail:Label>|error {
    gmail:ListLabelsResponse listResult = check gmailClient->/users/me/labels();
    map<gmail:Label> labelsByName = {};
    gmail:Label[]? labels = listResult.labels;
    if labels is gmail:Label[] {
        foreach gmail:Label label in labels {
            string? labelName = label.name;
            if labelName is string {
                labelsByName[labelName.toLowerAscii()] = label;
            }
        }
    }
    return labelsByName;
}

// Ensures all four category folders exist in the mailbox, creating any that are
// missing, and returns a map from category to its label identifier. Labels are
// looked up by name first so running the sweep twice never creates duplicates.
// Stops at the first category whose folder cannot be verified or created and
// reports which category failed, rather than filing against a partial set of folders.
function ensureCategoryFolders() returns map<string>|FilingSetupFailure {
    map<gmail:Label>|error existingLabels = fetchLabelsByName();
    if existingLabels is error {
        FilingSetupFailure setupFailure = {message: "folder setup failed", category: CATEGORY_FOLDERS[0].category};
        return setupFailure;
    }

    map<string> labelIdsByCategory = {};
    foreach CategoryFolder folder in CATEGORY_FOLDERS {
        gmail:Label? existingLabel = existingLabels[folder.labelName.toLowerAscii()];
        if existingLabel is gmail:Label {
            string? existingLabelId = existingLabel.id;
            if existingLabelId is string {
                labelIdsByCategory[folder.category] = existingLabelId;
                continue;
            }
        }

        gmail:Label|error createdLabel = gmailClient->/users/me/labels.post({
            name: folder.labelName,
            labelListVisibility: "labelShow",
            messageListVisibility: "show"
        });
        if createdLabel is error {
            FilingSetupFailure setupFailure = {message: string `folder setup failed for category '${folder.labelName}'`, category: folder.category};
            return setupFailure;
        }

        string? createdLabelId = createdLabel.id;
        if createdLabelId is () {
            FilingSetupFailure setupFailure = {message: string `folder setup failed for category '${folder.labelName}'`, category: folder.category};
            return setupFailure;
        }
        labelIdsByCategory[folder.category] = createdLabelId;
    }

    return labelIdsByCategory;
}

// Files a single already-unread message: adds the category's label and removes
// both UNREAD and INBOX so it is moved out of the inbox and will not be picked up
// by a later sweep, which only looks at unread inbox mail.
function fileMessage(string messageId, string labelId) returns error? {
    gmail:ModifyMessageRequest modifyRequest = {
        addLabelIds: [labelId],
        removeLabelIds: ["UNREAD", "INBOX"]
    };
    gmail:Message|error modifyResult = gmailClient->/users/me/messages/[messageId]/modify.post(modifyRequest);
    if modifyResult is error {
        return error("failed to file message");
    }
}

// Runs a full filing sweep: ensures the four category folders exist, classifies
// every unread inbox message by subject keyword or sender domain, then tags and
// marks each one read so a later sweep finds nothing left to do. If the folder
// setup fails, filing is stopped before anything is touched. Any other failure
// reaching the mailbox is collapsed into a single generic error.
function sweepAndFileUnreadMessages() returns FilingSweepResult|FilingSetupFailure|error {
    map<string>|FilingSetupFailure labelIdsByCategory = ensureCategoryFolders();
    if labelIdsByCategory is FilingSetupFailure {
        return labelIdsByCategory;
    }

    gmail:ListMessagesResponse|error listResult = gmailClient->/users/me/messages(q = "label:INBOX is:unread");
    if listResult is error {
        return error("triage is unavailable");
    }

    gmail:Message[]? messageRefs = listResult.messages;
    if messageRefs is () {
        return {filed: []};
    }

    FiledMessage[] filedMessages = [];
    foreach gmail:Message messageRef in messageRefs {
        gmail:Message|error fullMessage = gmailClient->/users/me/messages/[messageRef.id](
            format = "metadata",
            metadataHeaders = ["From", "Subject"]
        );
        if fullMessage is error {
            return error("triage is unavailable");
        }

        string subject = extractHeaderValue(fullMessage, "Subject");
        string sender = extractHeaderValue(fullMessage, "From");
        Category category = classifyMessage(subject, sender);
        string labelId = labelIdsByCategory.get(category);

        error? fileResult = fileMessage(fullMessage.id, labelId);
        if fileResult is error {
            return error("triage is unavailable");
        }

        filedMessages.push({messageId: fullMessage.id, category});
    }

    return {filed: filedMessages};
}
