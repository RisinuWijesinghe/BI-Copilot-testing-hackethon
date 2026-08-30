import ballerina/http;
import ballerina/log;

# Response returned when an issue is successfully filed on GitHub.
#
# + body - The created issue's number and URL
public type IssueCreated record {|
    *http:Created;
    CreatedIssue body;
|};

# Error payload returned to the caller.
#
# + message - Human-readable description of the failure
public type ErrorDetail record {|
    string message;
|};

# Response returned when GitHub rejects the request to file an issue, e.g. due to validation failure.
#
# + body - Details of why the request was rejected
public type IssueRejected record {|
    *http:UnprocessableEntity;
    ErrorDetail body;
|};

# Response returned when the request to file an issue could not be completed.
#
# + body - Details of the failure
public type IssueCreationFailed record {|
    *http:InternalServerError;
    ErrorDetail body;
|};

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

    # Files a new issue on a GitHub repository.
    #
    # + owner - Account owner of the repository
    # + repo - Name of the repository
    # + newIssue - Details of the issue to create
    # + return - The created issue's number and URL, a 422 payload if GitHub rejected the request, or a 500 payload
    # if the request otherwise could not be completed
    resource function post repos/[string owner]/[string repo]/issues(@http:Payload NewIssue newIssue)
            returns IssueCreated|IssueRejected|IssueCreationFailed {
        CreatedIssue|error createdIssue = createIssue(owner, repo, newIssue);
        if createdIssue is http:ClientRequestError {
            log:printError("GitHub rejected the issue creation request", createdIssue,
                    owner = owner, repo = repo);
            IssueRejected rejected = {
                body: {
                    message: string `GitHub rejected the request to create an issue for ${owner}/${repo}`
                }
            };
            return rejected;
        }
        if createdIssue is error {
            log:printError("failed to create issue on GitHub", createdIssue,
                    owner = owner, repo = repo);
            IssueCreationFailed creationFailed = {
                body: {
                    message: string `Failed to create issue for ${owner}/${repo}`
                }
            };
            return creationFailed;
        }
        IssueCreated created = {
            body: createdIssue
        };
        return created;
    }
}
