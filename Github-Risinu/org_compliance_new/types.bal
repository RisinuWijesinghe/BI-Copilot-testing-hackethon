// Result of a single compliance rule check for a repository.
public type RuleStatus "pass"|"fail"|"unknown";

// Branch protection rule check details.
public type BranchProtectionCheck record {|
    RuleStatus status;
    boolean requiresApprovingReview;
    int requiredApprovingReviewCount;
    boolean requiresStatusChecks;
    string details;
|};

// CODEOWNERS rule check details.
public type CodeownersCheck record {|
    RuleStatus status;
    string location;
    string details;
|};

// LICENSE rule check details.
public type LicenseCheck record {|
    RuleStatus status;
    string details;
|};

// Topics rule check details.
public type TopicsCheck record {|
    RuleStatus status;
    int topicCount;
    string details;
|};

// Hardcoded token scan rule check details.
public type WorkflowTokenScanCheck record {|
    RuleStatus status;
    string[] flaggedWorkflows;
    string details;
|};

// The full set of compliance checks performed against a single repository.
public type RepositoryComplianceChecks record {|
    BranchProtectionCheck branchProtection;
    CodeownersCheck codeowners;
    LicenseCheck license;
    TopicsCheck topics;
    WorkflowTokenScanCheck workflowTokenScan;
|};

// Compliance result for a single repository.
public type RepositoryComplianceResult record {|
    string name;
    string fullName;
    string defaultBranch;
    boolean compliant;
    RepositoryComplianceChecks checks;
|};

// Full organization compliance report.
public type ComplianceReport record {|
    string 'organization;
    string generatedAt;
    int totalRepositoriesScanned;
    int compliantRepositories;
    int nonCompliantRepositories;
    RepositoryComplianceResult[] repositories;
|};
