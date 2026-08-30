import ballerina/http;
import ballerina/time;
import ballerinax/github;

service /compliance on new http:Listener(9090) {

    # Scans every non-archived repository in the configured GitHub organization against the
    # compliance rules (branch protection, CODEOWNERS, LICENSE, topics, workflow token scan)
    # and returns the aggregated JSON report.
    #
    # + return - The organization compliance report, or an internal server error if the
    # repository listing could not be retrieved
    resource function get report() returns ComplianceReport|http:InternalServerError {
        github:MinimalRepository[]|error nonArchivedRepositories = fetchNonArchivedRepositories(githubOrg);
        if nonArchivedRepositories is error {
            return <http:InternalServerError>{
                body: {message: string `Failed to list repositories for org '${githubOrg}': ${nonArchivedRepositories.message()}`}
            };
        }

        RepositoryComplianceResult[] repositoryResults = [];
        int compliantCount = 0;
        foreach github:MinimalRepository repository in nonArchivedRepositories {
            RepositoryComplianceResult repositoryResult = scanRepository(repository);
            repositoryResults.push(repositoryResult);
            if repositoryResult.compliant {
                compliantCount += 1;
            }
        }

        int totalScanned = repositoryResults.length();
        return {
            'organization: githubOrg,
            generatedAt: time:utcToString(time:utcNow()),
            totalRepositoriesScanned: totalScanned,
            compliantRepositories: compliantCount,
            nonCompliantRepositories: totalScanned - compliantCount,
            repositories: repositoryResults
        };
    }

    # Remediates missing CODEOWNERS/LICENSE compliance issues for a single repository: creates
    # (or reuses) a branch off the default branch, commits the missing file(s) through the
    # contents API, and opens (or updates) a pull request listing the remediated checks.
    #
    # + owner - The repository owner (user or organization)
    # + repo - The repository name
    # + return - The remediation result, a message when no remediation was needed because the
    # repository already has both files, or an internal server error if remediation failed
    resource function post remediate/[string owner]/[string repo]() returns RemediationResult|RemediationNotNeeded|http:InternalServerError {
        RemediationResult|RemediationNotNeeded|error remediationOutcome = remediateRepository(owner, repo);
        if remediationOutcome is error {
            return <http:InternalServerError>{
                body: {message: string `Failed to remediate compliance issues for '${owner}/${repo}': ${remediationOutcome.message()}`}
            };
        }
        return remediationOutcome;
    }
}
