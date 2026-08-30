import ballerina/lang.array;
import ballerina/lang.regexp;
import ballerinax/github;

// Candidate locations where a CODEOWNERS file may live, in the order GitHub itself checks them.
final string[] codeownersLocations = [".github/CODEOWNERS", "docs/CODEOWNERS", "CODEOWNERS"];

// Patterns that indicate a hardcoded secret/token was committed directly into a workflow file,
// instead of being referenced via `secrets.*` or an environment variable.
final regexp:RegExp[] hardcodedTokenPatterns = [
    re `ghp_[A-Za-z0-9]{20,}`,
    re `gho_[A-Za-z0-9]{20,}`,
    re `ghu_[A-Za-z0-9]{20,}`,
    re `ghs_[A-Za-z0-9]{20,}`,
    re `ghr_[A-Za-z0-9]{20,}`,
    re `github_pat_[A-Za-z0-9_]{20,}`,
    re `xox[baprs]-[A-Za-z0-9-]{10,}`,
    re `AKIA[A-Z0-9]{16}`,
    re `AIza[A-Za-z0-9_-]{35}`,
    re `sk-[A-Za-z0-9]{20,}`
];

// Fetches every non-archived repository in the org, paging through the results properly.
function fetchNonArchivedRepositories(string org) returns github:MinimalRepository[]|error {
    github:MinimalRepository[] nonArchivedRepositories = [];
    int currentPage = 1;
    int perPage = 100;
    while true {
        github:MinimalRepository[] pageOfRepositories = check githubClient->/orgs/[org]/repos(perPage = perPage, page = currentPage, 'type = "all");
        if pageOfRepositories.length() == 0 {
            break;
        }
        foreach github:MinimalRepository repository in pageOfRepositories {
            boolean archived = repository.archived ?: false;
            if !archived {
                nonArchivedRepositories.push(repository);
            }
        }
        if pageOfRepositories.length() < perPage {
            break;
        }
        currentPage += 1;
    }
    return nonArchivedRepositories;
}

// Checks that the default branch has protection enabled with at least one required approving
// review and required status checks. A 403 (no admin rights) is reported as "unknown" rather
// than failing the whole scan.
function checkBranchProtection(string owner, string repo, string defaultBranch) returns BranchProtectionCheck {
    github:BranchProtection|error branchProtection = githubClient->/repos/[owner]/[repo]/branches/[defaultBranch]/protection;
    if branchProtection is error {
        string errorMessage = branchProtection.message();
        if errorMessage.includes("403") {
            return {
                status: "unknown",
                requiresApprovingReview: false,
                requiredApprovingReviewCount: 0,
                requiresStatusChecks: false,
                details: "Insufficient permissions (403) to read branch protection; admin rights required"
            };
        }
        return {
            status: "fail",
            requiresApprovingReview: false,
            requiredApprovingReviewCount: 0,
            requiresStatusChecks: false,
            details: string `Failed to fetch branch protection: ${errorMessage}`
        };
    }

    github:ProtectedBranchPullRequestReview? pullRequestReview = branchProtection.requiredPullRequestReviews;
    int requiredApprovingReviewCount = 0;
    if pullRequestReview is github:ProtectedBranchPullRequestReview {
        requiredApprovingReviewCount = pullRequestReview.requiredApprovingReviewCount ?: 0;
    }
    boolean requiresApprovingReview = requiredApprovingReviewCount >= 1;

    github:ProtectedBranchRequiredStatusCheck? requiredStatusCheck = branchProtection.requiredStatusChecks;
    boolean requiresStatusChecks = requiredStatusCheck is github:ProtectedBranchRequiredStatusCheck;

    if requiresApprovingReview && requiresStatusChecks {
        return {
            status: "pass",
            requiresApprovingReview,
            requiredApprovingReviewCount,
            requiresStatusChecks,
            details: "Branch protection enabled with required approving review and required status checks"
        };
    }

    string[] missingItems = [];
    if !requiresApprovingReview {
        missingItems.push("at least one required approving review");
    }
    if !requiresStatusChecks {
        missingItems.push("required status checks");
    }
    string missingList = string:'join(", ", ...missingItems);
    return {
        status: "fail",
        requiresApprovingReview,
        requiredApprovingReviewCount,
        requiresStatusChecks,
        details: string `Branch protection is missing: ${missingList}`
    };
}

// Checks whether a CODEOWNERS file exists in .github/, docs/, or the repo root.
function checkCodeowners(string owner, string repo) returns CodeownersCheck {
    foreach string location in codeownersLocations {
        github:ContentDirectory|github:ContentFile|github:ContentSymlink|github:ContentSubmodule|error?|() content = githubClient->/repos/[owner]/[repo]/contents/[location];
        if content is github:ContentFile {
            return {
                status: "pass",
                location,
                details: string `CODEOWNERS file found at ${location}`
            };
        }
    }
    return {
        status: "fail",
        location: "",
        details: "No CODEOWNERS file found in .github/, docs/, or the repo root"
    };
}

// Checks whether a LICENSE file exists for the repository.
function checkLicense(string owner, string repo) returns LicenseCheck {
    github:LicenseContent|error license = githubClient->/repos/[owner]/[repo]/license;
    if license is github:LicenseContent {
        return {
            status: "pass",
            details: string `LICENSE file found at ${license.path}`
        };
    }
    return {
        status: "fail",
        details: "No LICENSE file found"
    };
}

// Checks that the repository has at least one topic.
function checkTopics(string owner, string repo) returns TopicsCheck {
    github:Topic|error topicResult = githubClient->/repos/[owner]/[repo]/topics;
    if topicResult is error {
        return {
            status: "fail",
            topicCount: 0,
            details: string `Failed to fetch topics: ${topicResult.message()}`
        };
    }
    int topicCount = topicResult.names.length();
    if topicCount >= 1 {
        return {
            status: "pass",
            topicCount,
            details: string `Repository has ${topicCount} topic(s)`
        };
    }
    return {
        status: "fail",
        topicCount,
        details: "Repository has no topics"
    };
}

// Scans a single workflow file's content for hardcoded token patterns.
function workflowContainsHardcodedToken(string owner, string repo, string workflowPath) returns boolean|error {
    github:ContentDirectory|github:ContentFile|github:ContentSymlink|github:ContentSubmodule|error?|() content = check githubClient->/repos/[owner]/[repo]/contents/[workflowPath];
    if content is github:ContentFile {
        string base64Content = re `\n`.replaceAll(content.content, "");
        byte[]|error decodedBytes = array:fromBase64(base64Content);
        if decodedBytes is error {
            return decodedBytes;
        }
        string|error decodedContent = string:fromBytes(decodedBytes);
        if decodedContent is error {
            return decodedContent;
        }
        foreach regexp:RegExp tokenPattern in hardcodedTokenPatterns {
            if tokenPattern.isFullMatch(decodedContent) || tokenPattern.find(decodedContent) is regexp:Span {
                return true;
            }
        }
    }
    return false;
}

// Checks that no workflow file under .github/workflows contains a hardcoded token pattern.
function checkWorkflowTokens(string owner, string repo) returns WorkflowTokenScanCheck {
    github:WorkflowResponse|error workflowResponse = githubClient->/repos/[owner]/[repo]/actions/workflows(perPage = 100);
    if workflowResponse is error {
        return {
            status: "fail",
            flaggedWorkflows: [],
            details: string `Failed to list workflows: ${workflowResponse.message()}`
        };
    }

    github:Workflow[] workflows = workflowResponse.workflows;
    if workflows.length() == 0 {
        return {
            status: "pass",
            flaggedWorkflows: [],
            details: "No workflow files found"
        };
    }

    string[] flaggedWorkflows = [];
    foreach github:Workflow workflow in workflows {
        boolean|error scanResult = workflowContainsHardcodedToken(owner, repo, workflow.path);
        if scanResult is error {
            continue;
        }
        if scanResult {
            flaggedWorkflows.push(workflow.path);
        }
    }

    if flaggedWorkflows.length() == 0 {
        return {
            status: "pass",
            flaggedWorkflows: [],
            details: "No hardcoded token patterns found in workflow files"
        };
    }
    string flaggedList = string:'join(", ", ...flaggedWorkflows);
    return {
        status: "fail",
        flaggedWorkflows,
        details: string `Hardcoded token pattern(s) found in: ${flaggedList}`
    };
}

// Runs every compliance rule against a single repository and aggregates the results.
function scanRepository(github:MinimalRepository repository) returns RepositoryComplianceResult {
    string owner = repository.owner.login;
    string repoName = repository.name;
    string defaultBranch = repository.defaultBranch ?: "main";

    BranchProtectionCheck branchProtectionCheck = checkBranchProtection(owner, repoName, defaultBranch);
    CodeownersCheck codeownersCheck = checkCodeowners(owner, repoName);
    LicenseCheck licenseCheck = checkLicense(owner, repoName);
    TopicsCheck topicsCheck = checkTopics(owner, repoName);
    WorkflowTokenScanCheck workflowTokenScanCheck = checkWorkflowTokens(owner, repoName);

    RepositoryComplianceChecks checks = {
        branchProtection: branchProtectionCheck,
        codeowners: codeownersCheck,
        license: licenseCheck,
        topics: topicsCheck,
        workflowTokenScan: workflowTokenScanCheck
    };

    boolean compliant = branchProtectionCheck.status != "fail" &&
        codeownersCheck.status != "fail" &&
        licenseCheck.status != "fail" &&
        topicsCheck.status != "fail" &&
        workflowTokenScanCheck.status != "fail";

    return {
        name: repoName,
        fullName: repository.fullName,
        defaultBranch,
        compliant,
        checks
    };
}
