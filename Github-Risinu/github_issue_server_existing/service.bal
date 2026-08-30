import ballerina/http;
import ballerina/log;

service / on new http:Listener(8080) {

    # Returns the open issues of a GitHub repository.
    #
    # + owner - Account owner of the repository
    # + repo - Name of the repository
    # + return - The open issues, or an error payload if GitHub could not be reached
    resource function get repos/[string owner]/[string repo]/issues()
            returns IssueSummary[]|http:InternalServerError {
        IssueSummary[]|error issues = getOpenIssues(owner, repo);
        if issues is error {
            log:printError("failed to retrieve issues from GitHub", issues,
                    owner = owner, repo = repo);
            return {
                body: {
                    message: string `Failed to retrieve issues for ${owner}/${repo}`
                }
            };
        }
        return issues;
    }
}
