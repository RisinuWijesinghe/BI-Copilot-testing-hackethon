configurable string gmailClientId = ?;
configurable string gmailClientSecret = ?;
configurable string gmailRefreshToken = ?;
configurable string gmailRefreshUrl = "https://oauth2.googleapis.com/token";

configurable int servicePort = 8080;

// Keyword and sender-domain rules used to sort swept messages into categories.
// Each list is comma-separated; matching is case-insensitive. A message is filed
// under the first category (in billing, bugs, sales order) whose subject contains
// one of its keywords or whose sender domain is one of its domains. Anything that
// matches none of them is filed under the "everything-else" catch-all category.
configurable string billingSubjectKeywords = "invoice,billing,payment,receipt,refund";
configurable string billingSenderDomains = "";

configurable string bugsSubjectKeywords = "bug,error,crash,broken,issue,defect";
configurable string bugsSenderDomains = "";

configurable string salesSubjectKeywords = "quote,pricing,demo,proposal,deal,purchase";
configurable string salesSenderDomains = "";
