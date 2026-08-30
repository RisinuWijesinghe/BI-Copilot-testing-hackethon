import ballerina/lang.regexp;
import ballerina/lang.runtime;
import ballerinax/github;

// Terminal check-run conclusions that indicate the check did not succeed.
final string[] nonSuccessfulCheckConclusions = ["failure", "cancelled", "timed_out", "action_required"];

// Conventional commit header pattern: type(optional scope)(optional !): description
final regexp:RegExp conventionalCommitPattern = re `^(feat|fix|perf|chore)(\([^)]*\))?!?:\s*(.*)$`;

// Extracts the first line of a commit message.
function getCommitSubject(string fullMessage) returns string {
    string[] lines = re `\n`.split(fullMessage);
    if lines.length() > 0 {
        return lines[0];
    }
    return fullMessage;
}

// Resolves the author display name for a commit, falling back sensibly when data is missing.
function resolveCommitAuthor(github:Commit gitCommit) returns string {
    github:NullableSimpleUser? commitAuthorAccount = gitCommit.author;
    if commitAuthorAccount is github:NullableSimpleUser {
        return commitAuthorAccount.login;
    }
    github:CommitCommit innerCommit = gitCommit.'commit;
    github:NullableGitUser? rawAuthor = innerCommit.author;
    if rawAuthor is github:NullableGitUser {
        string? rawAuthorName = rawAuthor.name;
        if rawAuthorName is string {
            return rawAuthorName;
        }
    }
    return "unknown";
}

// Builds a changelog grouped by conventional-commit type from a list of commits.
function buildChangelog(github:Commit[] commits) returns Changelog {
    ChangelogEntry[] featEntries = [];
    ChangelogEntry[] fixEntries = [];
    ChangelogEntry[] perfEntries = [];
    ChangelogEntry[] choreEntries = [];
    ChangelogEntry[] otherEntries = [];

    foreach github:Commit gitCommit in commits {
        string commitSha = gitCommit.sha;
        string shortSha = commitSha.length() >= 7 ? commitSha.substring(0, 7) : commitSha;
        github:CommitCommit innerCommit = gitCommit.'commit;
        string fullMessage = innerCommit.message;
        string subject = getCommitSubject(fullMessage);
        string author = resolveCommitAuthor(gitCommit);

        ChangelogEntry entry = {
            shortSha: shortSha,
            message: subject,
            author: author
        };

        regexp:Groups? groups = conventionalCommitPattern.findGroups(subject);
        if groups is regexp:Groups {
            regexp:Span? typeSpan = groups[1];
            string commitType = typeSpan is regexp:Span ? typeSpan.substring() : "";
            regexp:Span? descriptionSpan = groups[3];
            string description = descriptionSpan is regexp:Span ? descriptionSpan.substring() : subject;
            ChangelogEntry conventionalEntry = {
                shortSha: shortSha,
                message: description,
                author: author
            };
            if commitType == "feat" {
                featEntries.push(conventionalEntry);
            } else if commitType == "fix" {
                fixEntries.push(conventionalEntry);
            } else if commitType == "perf" {
                perfEntries.push(conventionalEntry);
            } else if commitType == "chore" {
                choreEntries.push(conventionalEntry);
            } else {
                otherEntries.push(entry);
            }
        } else {
            otherEntries.push(entry);
        }
    }

    return {
        feat: featEntries,
        fix: fixEntries,
        perf: perfEntries,
        chore: choreEntries,
        other: otherEntries
    };
}

// Renders a single changelog section as markdown, returning an empty string when there are no entries.
function renderChangelogSection(string title, ChangelogEntry[] entries) returns string {
    if entries.length() == 0 {
        return "";
    }
    string section = string `## ${title}` + "\n";
    foreach ChangelogEntry entry in entries {
        section += string `- ${entry.message} (${entry.shortSha}) by @${entry.author}` + "\n";
    }
    return section + "\n";
}

// Renders the full changelog as a markdown document to be used as the release body.
function renderChangelog(Changelog changelog) returns string {
    string body = "";
    body += renderChangelogSection("Features", changelog.feat);
    body += renderChangelogSection("Bug Fixes", changelog.fix);
    body += renderChangelogSection("Performance Improvements", changelog.perf);
    body += renderChangelogSection("Chores", changelog.chore);
    body += renderChangelogSection("Other Changes", changelog.other);
    if body == "" {
        return "No changes.";
    }
    return body.trim();
}

// Verifies the combined commit status for the given ref, failing unless every status has succeeded.
function verifyCombinedStatus(string owner, string repo, string headSha) returns string?|error {
    github:CombinedCommitStatus combinedStatus = check githubClient->/repos/[owner]/[repo]/commits/[headSha]/status;
    if combinedStatus.state != "success" {
        github:SimpleCommitStatus[] statuses = combinedStatus.statuses;
        string[] failingContexts = [];
        foreach github:SimpleCommitStatus statusEntry in statuses {
            if statusEntry.state != "success" {
                failingContexts.push(string `${statusEntry.context} (${statusEntry.state})`);
            }
        }
        string failingList = string:'join(", ", ...failingContexts);
        return string `Combined status for ${headSha} is '${combinedStatus.state}'. Failing/pending contexts: ${failingList}`;
    }
    return ();
}

// Verifies every required check run for the given ref has completed successfully.
function verifyCheckRuns(string owner, string repo, string headSha) returns string?|error {
    github:CheckRunResponse checkRunResponse = check githubClient->/repos/[owner]/[repo]/commits/[headSha]/check\-runs(filter = "latest");
    github:CheckRun[] checkRuns = checkRunResponse.checkRuns;
    string[] failingChecks = [];
    foreach github:CheckRun checkRun in checkRuns {
        if checkRun.status != "completed" {
            failingChecks.push(string `${checkRun.name} (${checkRun.status})`);
            continue;
        }
        string? conclusion = checkRun.conclusion;
        if conclusion is () {
            failingChecks.push(string `${checkRun.name} (no conclusion)`);
            continue;
        }
        boolean isNonSuccessful = nonSuccessfulCheckConclusions.indexOf(conclusion) is int;
        if isNonSuccessful {
            failingChecks.push(string `${checkRun.name} (${conclusion})`);
        }
    }
    if failingChecks.length() > 0 {
        string failingList = string:'join(", ", ...failingChecks);
        return string `Required check run(s) have not succeeded for ${headSha}: ${failingList}`;
    }
    return ();
}

// Locates the workflow run that was just dispatched for the given tag by picking the most recently
// created run for that workflow file triggered by a workflow_dispatch event against the tag ref.
function findDispatchedWorkflowRun(string owner, string repo, string workflowFile, string tagName, int maxAttempts, decimal pollIntervalSeconds) returns github:WorkflowRun|error {
    string workflowPathSuffix = string `/${workflowFile}`;
    int attempt = 0;
    while attempt < maxAttempts {
        github:WorkflowRunResponse runsResponse = check githubClient->/repos/[owner]/[repo]/actions/runs(event = "workflow_dispatch", branch = tagName, perPage = 10);
        github:WorkflowRun[] workflowRuns = runsResponse.workflowRuns;
        foreach github:WorkflowRun workflowRun in workflowRuns {
            if workflowRun.path.endsWith(workflowPathSuffix) {
                return workflowRun;
            }
        }
        attempt += 1;
        if attempt < maxAttempts {
            runtime:sleep(pollIntervalSeconds);
        }
    }
    return error(string `Timed out waiting for a dispatched run of '${workflowFile}' against '${tagName}' in ${owner}/${repo} to appear`);
}

// Polls a workflow run until it reaches a terminal (completed) state, or the attempt budget is exhausted.
function awaitWorkflowRunCompletion(string owner, string repo, int runId, int maxAttempts, decimal pollIntervalSeconds) returns github:WorkflowRun|error {
    int attempt = 0;
    while attempt < maxAttempts {
        github:WorkflowRunResponse runsResponse = check githubClient->/repos/[owner]/[repo]/actions/runs(perPage = 30);
        github:WorkflowRun[] workflowRuns = runsResponse.workflowRuns;
        foreach github:WorkflowRun workflowRun in workflowRuns {
            if workflowRun.id == runId {
                string? runStatus = workflowRun.status;
                if runStatus is string && runStatus == "completed" {
                    return workflowRun;
                }
                break;
            }
        }
        attempt += 1;
        if attempt < maxAttempts {
            runtime:sleep(pollIntervalSeconds);
        }
    }
    return error(string `Timed out waiting for workflow run ${runId} in ${owner}/${repo} to complete`);
}
