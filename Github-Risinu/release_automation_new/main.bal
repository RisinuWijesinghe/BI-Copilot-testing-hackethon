import ballerina/file;
import ballerina/http;
import ballerina/io;
import ballerina/log;
import ballerinax/github;

service /releases on new http:Listener(9090) {

    # Cuts a new release by finding the previous published release, building a changelog of every
    # commit since that release, verifying the head commit's combined status and check runs, creating
    # an annotated tag, publishing a draft GitHub release with the build artifact attached, running the
    # post-release smoke test workflow against the new tag, and publishing the release once it succeeds.
    #
    # + request - The release-cut request containing owner, repo, semver version, and artifact path
    # + return - The created release details, a conflict error if the tag already exists, an unprocessable
    # entity error if the head commit is not safe to release, or a generic error
    resource function post cut(@http:Payload CutReleaseRequest request) returns CutReleaseResponse|http:Conflict|http:UnprocessableEntity|http:InternalServerError {
        string owner = request.owner;
        string repo = request.repo;
        string version = request.version;
        string targetBranch = request.targetBranch;
        string tagName = version.startsWith("v") ? version : string `v${version}`;
        string idempotencyKey = string `${owner}/${repo}/${tagName}`;

        // 0. Idempotency short-circuit: replay the cached terminal outcome of a previous call with the
        // same owner/repo/version instead of repeating any side effect.
        CutReleaseOutcome? cachedOutcome = getCachedOutcome(idempotencyKey);
        if cachedOutcome is CutReleaseOutcome {
            return toCutReleaseResult(cachedOutcome);
        }

        // 1. Fail fast if the tag/release already exists, without caching (so unrelated pre-existing
        // tags remain a plain conflict rather than being remembered as this endpoint's own outcome).
        github:Release?|error existingReleaseResult = findReleaseByTag(owner, repo, tagName);
        if existingReleaseResult is error {
            string errorMessage = string `Failed to check for an existing release for '${tagName}' in ${owner}/${repo}: ${existingReleaseResult.message()}`;
            log:printError(errorMessage);
            return <http:InternalServerError>{
                body: {message: errorMessage}
            };
        }
        if existingReleaseResult is github:Release {
            github:Release existingRelease = existingReleaseResult;
            if !existingRelease.draft {
                CutReleaseResponse response = {
                    tagName: tagName,
                    previousTagName: "",
                    releaseUrl: existingRelease.url,
                    releaseHtmlUrl: existingRelease.htmlUrl,
                    draft: existingRelease.draft,
                    changelogBody: existingRelease?.body ?: "",
                    smokeTestWorkflowRunUrl: ""
                };
                cacheOutcome(idempotencyKey, {response});
                return response;
            }
            string conflictMessage = string `Release '${tagName}' already exists as a draft in ${owner}/${repo}; a previous cut is still in progress or was left incomplete`;
            log:printWarn(conflictMessage);
            return <http:Conflict>{
                body: {message: conflictMessage}
            };
        }
        github:GitRef|error existingRef = githubClient->/repos/[owner]/[repo]/git/ref/["tags/" + tagName];
        if existingRef is github:GitRef {
            string conflictMessage = string `Tag '${tagName}' already exists in ${owner}/${repo} without a matching release`;
            log:printWarn(conflictMessage);
            return <http:Conflict>{
                body: {message: conflictMessage}
            };
        }

        // 2. Find the most recent published release to use as the previous tag.
        github:Release|error latestRelease = githubClient->/repos/[owner]/[repo]/releases/latest;
        string previousTagName;
        if latestRelease is github:Release {
            previousTagName = latestRelease.tagName;
        } else {
            log:printWarn(string `No previous published release found for ${owner}/${repo}, treating as first release`);
            previousTagName = "";
        }

        // 3. Resolve the head commit SHA of the target branch.
        github:GitRef|error headRef = githubClient->/repos/[owner]/[repo]/git/ref/["heads/" + targetBranch];
        if headRef is error {
            string errorMessage = string `Failed to resolve head of branch '${targetBranch}' in ${owner}/${repo}: ${headRef.message()}`;
            log:printError(errorMessage);
            return <http:InternalServerError>{
                body: {message: errorMessage}
            };
        }
        string headSha = headRef.'object.sha;

        // 4. Verify it is safe to proceed: the combined status and every required check run for the
        // head commit must have succeeded before a tag is created.
        string?|error combinedStatusFailure = verifyCombinedStatus(owner, repo, headSha);
        if combinedStatusFailure is error {
            string errorMessage = string `Failed to fetch combined status for ${headSha} in ${owner}/${repo}: ${combinedStatusFailure.message()}`;
            log:printError(errorMessage);
            return <http:InternalServerError>{
                body: {message: errorMessage}
            };
        }
        if combinedStatusFailure is string {
            log:printWarn(combinedStatusFailure);
            return <http:UnprocessableEntity>{
                body: {message: combinedStatusFailure}
            };
        }

        string?|error checkRunsFailure = verifyCheckRuns(owner, repo, headSha);
        if checkRunsFailure is error {
            string errorMessage = string `Failed to fetch check runs for ${headSha} in ${owner}/${repo}: ${checkRunsFailure.message()}`;
            log:printError(errorMessage);
            return <http:InternalServerError>{
                body: {message: errorMessage}
            };
        }
        if checkRunsFailure is string {
            log:printWarn(checkRunsFailure);
            return <http:UnprocessableEntity>{
                body: {message: checkRunsFailure}
            };
        }

        // 5. List every commit between the previous tag and the target branch head.
        github:Commit[] commits;
        if previousTagName != "" {
            string basehead = string `${previousTagName}...${headSha}`;
            github:CommitComparison|error comparison = githubClient->/repos/[owner]/[repo]/compare/[basehead];
            if comparison is error {
                string errorMessage = string `Failed to compare '${previousTagName}' with '${headSha}' in ${owner}/${repo}: ${comparison.message()}`;
                log:printError(errorMessage);
                return <http:InternalServerError>{
                    body: {message: errorMessage}
                };
            }
            commits = comparison.commits;
        } else {
            github:Commit[]|error allCommits = githubClient->/repos/[owner]/[repo]/commits(sha = headSha);
            if allCommits is error {
                string errorMessage = string `Failed to list commits for ${owner}/${repo}: ${allCommits.message()}`;
                log:printError(errorMessage);
                return <http:InternalServerError>{
                    body: {message: errorMessage}
                };
            }
            commits = allCommits;
        }

        // 6. Build the changelog grouped by conventional-commit type.
        Changelog changelog = buildChangelog(commits);
        string changelogBody = renderChangelog(changelog);

        // 7. Create an annotated tag object pointing at the head commit.
        github:GitTagsBody tagPayload = {
            tag: tagName,
            message: string `Release ${tagName}`,
            'object: headSha,
            'type: "commit"
        };
        github:GitTag|error createdTag = githubClient->/repos/[owner]/[repo]/git/tags.post(tagPayload);
        if createdTag is error {
            string errorMessage = string `Failed to create annotated tag '${tagName}' in ${owner}/${repo}: ${createdTag.message()}`;
            log:printError(errorMessage);
            return <http:InternalServerError>{
                body: {message: errorMessage}
            };
        }

        // 8. Create the matching refs/tags/ ref pointing at the tag object.
        github:GitRefsBody refPayload = {
            ref: string `refs/tags/${tagName}`,
            sha: createdTag.sha
        };
        github:GitRef|error createdRef = githubClient->/repos/[owner]/[repo]/git/refs.post(refPayload);
        if createdRef is error {
            string errorMessage = string `Failed to create ref 'refs/tags/${tagName}' in ${owner}/${repo}: ${createdRef.message()}`;
            log:printError(errorMessage);
            return <http:InternalServerError>{
                body: {message: errorMessage}
            };
        }

        // 9. Create a draft GitHub release with the changelog as the body.
        github:RepoReleasesBody releasePayload = {
            tagName: tagName,
            targetCommitish: headSha,
            name: tagName,
            body: changelogBody,
            draft: true
        };
        github:Release|error createdRelease = githubClient->/repos/[owner]/[repo]/releases.post(releasePayload);
        if createdRelease is error {
            string errorMessage = string `Failed to create draft release '${tagName}' in ${owner}/${repo}: ${createdRelease.message()}`;
            log:printError(errorMessage);
            return <http:InternalServerError>{
                body: {message: errorMessage}
            };
        }
        int releaseId = createdRelease.id;

        // 10. Upload the build artifact at the given file path as a release asset.
        byte[]|error artifactBytes = io:fileReadBytes(request.artifactPath);
        if artifactBytes is error {
            string errorMessage = string `Failed to read artifact at '${request.artifactPath}': ${artifactBytes.message()}`;
            log:printError(errorMessage);
            return <http:InternalServerError>{
                body: {message: errorMessage}
            };
        }
        string|error artifactName = file:basename(request.artifactPath);
        if artifactName is error {
            string errorMessage = string `Failed to derive artifact name from '${request.artifactPath}': ${artifactName.message()}`;
            log:printError(errorMessage);
            return <http:InternalServerError>{
                body: {message: errorMessage}
            };
        }
        github:ReleaseAsset|error uploadedAsset = githubClient->/repos/[owner]/[repo]/releases/[releaseId]/assets.post(artifactBytes, name = artifactName);
        if uploadedAsset is error {
            string errorMessage = string `Failed to upload release asset '${artifactName}' for '${tagName}' in ${owner}/${repo}: ${uploadedAsset.message()}`;
            log:printError(errorMessage);
            return <http:InternalServerError>{
                body: {message: errorMessage}
            };
        }

        // 11. Trigger the post-release smoke test workflow via workflow dispatch against the new tag.
        github:WorkflowIdDispatchesBody dispatchPayload = {
            ref: tagName
        };
        error? dispatchResult = githubClient->/repos/[owner]/[repo]/actions/workflows/[smokeTestWorkflowFile]/dispatches.post(dispatchPayload);
        if dispatchResult is error {
            string errorMessage = string `Failed to dispatch workflow '${smokeTestWorkflowFile}' against '${tagName}' in ${owner}/${repo}: ${dispatchResult.message()}`;
            log:printError(errorMessage);
            return <http:InternalServerError>{
                body: {message: errorMessage}
            };
        }

        // 12. Locate the dispatched run and follow it until it concludes, backing off between polls
        // instead of spinning, bounded by the smoke test timeout.
        github:WorkflowRun|error dispatchedRun = findDispatchedWorkflowRun(owner, repo, smokeTestWorkflowFile, tagName, smokeTestTimeoutSeconds);
        if dispatchedRun is error {
            string errorMessage = string `Failed to locate the dispatched run of '${smokeTestWorkflowFile}' for '${tagName}' in ${owner}/${repo}: ${dispatchedRun.message()}`;
            log:printError(errorMessage);
            return <http:InternalServerError>{
                body: {message: errorMessage}
            };
        }
        github:WorkflowRun|error completedRun = awaitWorkflowRunCompletion(owner, repo, dispatchedRun.id, smokeTestTimeoutSeconds);
        if completedRun is error {
            // The smoke test did not conclude within the timeout: roll back the tag and draft release.
            FailedJob[]|error failedJobsResult = listFailedJobs(owner, repo, dispatchedRun.id);
            FailedJob[] failedJobs = failedJobsResult is FailedJob[] ? failedJobsResult : [];
            string|error rollbackResult = rollbackRelease(owner, repo, version, tagName, releaseId, dispatchedRun.htmlUrl, failedJobs);
            string errorMessage = rollbackResult is string
                ? string `Smoke test workflow run for '${tagName}' in ${owner}/${repo} did not conclude within the timeout. Release rolled back. Rollback issue: ${rollbackResult}`
                : string `Smoke test workflow run for '${tagName}' in ${owner}/${repo} did not conclude within the timeout. ${rollbackResult.message()}`;
            log:printError(errorMessage);
            cacheOutcome(idempotencyKey, {'error: {message: errorMessage}, statusCode: 500});
            return <http:InternalServerError>{
                body: {message: errorMessage}
            };
        }

        // 13. Publish the draft release only if the smoke test workflow run succeeded; otherwise roll back.
        string? runConclusion = completedRun.conclusion;
        if runConclusion is () || runConclusion != "success" {
            string conclusionText = runConclusion is string ? runConclusion : "unknown";
            FailedJob[]|error failedJobsResult = listFailedJobs(owner, repo, completedRun.id);
            FailedJob[] failedJobs = failedJobsResult is FailedJob[] ? failedJobsResult : [];
            string|error rollbackResult = rollbackRelease(owner, repo, version, tagName, releaseId, completedRun.htmlUrl, failedJobs);
            string errorMessage = rollbackResult is string
                ? string `Smoke test workflow run for '${tagName}' in ${owner}/${repo} concluded with '${conclusionText}'. Release rolled back. Rollback issue: ${rollbackResult}`
                : string `Smoke test workflow run for '${tagName}' in ${owner}/${repo} concluded with '${conclusionText}'. ${rollbackResult.message()}`;
            log:printError(errorMessage);
            cacheOutcome(idempotencyKey, {'error: {message: errorMessage}, statusCode: 500});
            return <http:InternalServerError>{
                body: {message: errorMessage}
            };
        }

        github:ReleasesreleaseIdBody publishPayload = {
            draft: false
        };
        github:Release|error publishedRelease = githubClient->/repos/[owner]/[repo]/releases/[releaseId].patch(publishPayload);
        if publishedRelease is error {
            string errorMessage = string `Smoke test succeeded but failed to publish release '${tagName}' in ${owner}/${repo}: ${publishedRelease.message()}`;
            log:printError(errorMessage);
            return <http:InternalServerError>{
                body: {message: errorMessage}
            };
        }

        CutReleaseResponse successResponse = {
            tagName: tagName,
            previousTagName: previousTagName,
            releaseUrl: publishedRelease.url,
            releaseHtmlUrl: publishedRelease.htmlUrl,
            draft: publishedRelease.draft,
            changelogBody: changelogBody,
            smokeTestWorkflowRunUrl: completedRun.htmlUrl
        };
        cacheOutcome(idempotencyKey, {response: successResponse});
        return successResponse;
    }
}
