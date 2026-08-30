import ballerina/http;
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

// Computes the next back-off delay, capped at the configured maximum, so polling loops slow down
// over time instead of spinning at a constant rate.
function nextBackOffInterval(decimal currentIntervalSeconds) returns decimal {
    decimal nextInterval = currentIntervalSeconds * workflowRunPollBackOffFactor;
    if nextInterval > workflowRunPollMaxIntervalSeconds {
        return workflowRunPollMaxIntervalSeconds;
    }
    return nextInterval;
}

// Locates the workflow run that was just dispatched for the given tag by picking the most recently
// created run for that workflow file triggered by a workflow_dispatch event against the tag ref.
// Polling backs off exponentially instead of spinning at a fixed rate, bounded by deadlineSeconds.
function findDispatchedWorkflowRun(string owner, string repo, string workflowFile, string tagName, decimal deadlineSeconds) returns github:WorkflowRun|error {
    string workflowPathSuffix = string `/${workflowFile}`;
    decimal elapsedSeconds = 0;
    decimal intervalSeconds = workflowRunPollInitialIntervalSeconds;
    while true {
        github:WorkflowRunResponse runsResponse = check githubClient->/repos/[owner]/[repo]/actions/runs(event = "workflow_dispatch", branch = tagName, perPage = 10);
        github:WorkflowRun[] workflowRuns = runsResponse.workflowRuns;
        foreach github:WorkflowRun workflowRun in workflowRuns {
            if workflowRun.path.endsWith(workflowPathSuffix) {
                return workflowRun;
            }
        }
        if elapsedSeconds >= deadlineSeconds {
            break;
        }
        runtime:sleep(intervalSeconds);
        elapsedSeconds += intervalSeconds;
        intervalSeconds = nextBackOffInterval(intervalSeconds);
    }
    return error(string `Timed out waiting for a dispatched run of '${workflowFile}' against '${tagName}' in ${owner}/${repo} to appear`);
}

// Polls a workflow run until it reaches a terminal (completed) state, or the deadline is exhausted.
// Uses an exponential back-off between polls instead of a fixed interval to avoid spinning.
function awaitWorkflowRunCompletion(string owner, string repo, int runId, decimal deadlineSeconds) returns github:WorkflowRun|error {
    decimal elapsedSeconds = 0;
    decimal intervalSeconds = workflowRunPollInitialIntervalSeconds;
    while true {
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
        if elapsedSeconds >= deadlineSeconds {
            break;
        }
        runtime:sleep(intervalSeconds);
        elapsedSeconds += intervalSeconds;
        intervalSeconds = nextBackOffInterval(intervalSeconds);
    }
    return error(string `Timed out waiting for workflow run ${runId} in ${owner}/${repo} to complete`);
}

// Looks up an existing release for the given tag, returning () when no such release exists.
function findReleaseByTag(string owner, string repo, string tagName) returns github:Release?|error {
    github:Release|error release = githubClient->/repos/[owner]/[repo]/releases/tags/[tagName];
    if release is github:Release {
        return release;
    }
    return ();
}

// Lists the jobs that did not succeed within a concluded workflow run.
function listFailedJobs(string owner, string repo, int runId) returns FailedJob[]|error {
    github:JobResponse jobResponse = check githubClient->/repos/[owner]/[repo]/actions/runs/[runId]/jobs(filter = "latest");
    github:Job[] jobs = jobResponse.jobs;
    FailedJob[] failedJobs = [];
    foreach github:Job jobEntry in jobs {
        string? conclusion = jobEntry.conclusion;
        boolean isNonSuccessful = conclusion is string && nonSuccessfulCheckConclusions.indexOf(conclusion) is int;
        if isNonSuccessful {
            string? jobHtmlUrl = jobEntry.htmlUrl;
            failedJobs.push({
                name: jobEntry.name,
                htmlUrl: jobHtmlUrl is string ? jobHtmlUrl : ""
            });
        }
    }
    return failedJobs;
}

// Converts a cached outcome into the HTTP response the resource function should return, so a retry
// with the same owner/repo/version replays the original result exactly.
function toCutReleaseResult(CutReleaseOutcome outcome) returns CutReleaseResponse|http:Conflict|http:UnprocessableEntity|http:InternalServerError {
    if outcome is record {| CutReleaseResponse response; |} {
        return outcome.response;
    }
    CutReleaseError cachedError = outcome.'error;
    int statusCode = outcome.statusCode;
    if statusCode == http:STATUS_CONFLICT {
        return <http:Conflict>{
            body: cachedError
        };
    }
    if statusCode == http:STATUS_UNPROCESSABLE_ENTITY {
        return <http:UnprocessableEntity>{
            body: cachedError
        };
    }
    return <http:InternalServerError>{
        body: cachedError
    };
}

// Rolls back a release attempt: deletes the draft release and the tag ref, then opens an issue
// documenting the failure, assigned to the release manager. Returns the rollback issue's HTML URL.
function rollbackRelease(string owner, string repo, string version, string tagName, int releaseId, string workflowRunHtmlUrl, FailedJob[] failedJobs) returns string|error {
    error? releaseDeletion = githubClient->/repos/[owner]/[repo]/releases/[releaseId].delete();
    if releaseDeletion is error {
        return error(string `Rollback failed: could not delete draft release '${tagName}' in ${owner}/${repo}: ${releaseDeletion.message()}`);
    }

    error? refDeletion = githubClient->/repos/[owner]/[repo]/git/refs/["tags/" + tagName].delete();
    if refDeletion is error {
        return error(string `Rollback failed: deleted draft release but could not delete ref 'refs/tags/${tagName}' in ${owner}/${repo}: ${refDeletion.message()}`);
    }

    string failedJobLines = failedJobs.length() > 0 ? "" : "- (no failed jobs reported)";
    foreach FailedJob failedJob in failedJobs {
        failedJobLines += string `- ${failedJob.name} (${failedJob.htmlUrl})` + "\n";
    }
    string issueBody = string `The post-release smoke test workflow run did not succeed, so release '${tagName}' has been rolled back.` + "\n\n" +
        string `Workflow run: ${workflowRunHtmlUrl}` + "\n\n" +
        "Failed jobs:" + "\n" + failedJobLines;

    github:RepoIssuesBody issuePayload = {
        title: string `Release ${version} rolled back`,
        body: issueBody,
        assignees: [releaseManagerGithubUsername]
    };
    github:Issue|error createdIssue = githubClient->/repos/[owner]/[repo]/issues.post(issuePayload);
    if createdIssue is error {
        return error(string `Rollback completed but failed to create the rollback issue for '${tagName}' in ${owner}/${repo}: ${createdIssue.message()}`);
    }
    return createdIssue.htmlUrl;
}
