import ballerina/http;
import ballerina/log;
import ballerinax/github;

service /releases on new http:Listener(9090) {

    # Cuts a new release by finding the previous published release, building a changelog of every
    # commit since that release, creating an annotated tag, and publishing a draft GitHub release.
    #
    # + request - The release-cut request containing owner, repo, and semver version
    # + return - The created release details, a conflict error if the tag already exists, or a generic error
    resource function post cut(@http:Payload CutReleaseRequest request) returns CutReleaseResponse|http:Conflict|http:InternalServerError {
        string owner = request.owner;
        string repo = request.repo;
        string version = request.version;
        string targetBranch = request.targetBranch;
        string tagName = version.startsWith("v") ? version : string `v${version}`;

        // 1. Fail fast if the tag already exists.
        github:GitRef|error existingRef = githubClient->/repos/[owner]/[repo]/git/ref/["tags/" + tagName];
        if existingRef is github:GitRef {
            string conflictMessage = string `Tag '${tagName}' already exists in ${owner}/${repo}`;
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

        // 4. List every commit between the previous tag and the target branch head.
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

        // 5. Build the changelog grouped by conventional-commit type.
        Changelog changelog = buildChangelog(commits);
        string changelogBody = renderChangelog(changelog);

        // 6. Create an annotated tag object pointing at the head commit.
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

        // 7. Create the matching refs/tags/ ref pointing at the tag object.
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

        // 8. Create a draft GitHub release with the changelog as the body.
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

        return {
            tagName: tagName,
            previousTagName: previousTagName,
            releaseUrl: createdRelease.url,
            releaseHtmlUrl: createdRelease.htmlUrl,
            draft: createdRelease.draft,
            changelogBody: changelogBody
        };
    }
}
