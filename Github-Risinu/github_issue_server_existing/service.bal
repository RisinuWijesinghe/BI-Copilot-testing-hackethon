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

# Response returned when a comment is successfully posted on an issue.
#
# + body - The created comment's number and URL
public type CommentCreated record {|
    *http:Created;
    CreatedComment body;
|};

# Response returned when GitHub rejects the request to post a comment, e.g. due to validation failure.
#
# + body - Details of why the request was rejected
public type CommentRejected record {|
    *http:UnprocessableEntity;
    ErrorDetail body;
|};

# Response returned when the request to post a comment could not be completed.
#
# + body - Details of the failure
public type CommentCreationFailed record {|
    *http:InternalServerError;
    ErrorDetail body;
|};

service / on new http:Listener(8080) {

    # Returns the open issues of a GitHub repository.
    #
    # + owner - Account owner of the repository
    # + repo - Name of the repository
    # + label - Optional label to filter the issues by
    # + return - The open issues, or an error payload if GitHub could not be reached
    resource function get repos/[string owner]/[string repo]/issues(string? label = ())
            returns IssueSummary[]|http:InternalServerError {
        IssueSummary[]|error issues = getOpenIssues(owner, repo, label);
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

    # Posts a comment on an existing GitHub issue.
    #
    # + owner - Account owner of the repository
    # + repo - Name of the repository
    # + issueNumber - Number of the issue to comment on
    # + newComment - Details of the comment to create
    # + return - The created comment's number and URL, a 422 payload if GitHub rejected the request, or a 500
    # payload if the request otherwise could not be completed
    resource function post repos/[string owner]/[string repo]/issues/[int issueNumber]/comments(
            @http:Payload NewComment newComment)
            returns CommentCreated|CommentRejected|CommentCreationFailed {
        CreatedComment|error createdComment = createComment(owner, repo, issueNumber, newComment);
        if createdComment is http:ClientRequestError {
            log:printError("GitHub rejected the comment creation request", createdComment,
                    owner = owner, repo = repo, issueNumber = issueNumber);
            CommentRejected rejected = {
                body: {
                    message: string `GitHub rejected the request to comment on issue ${issueNumber} for ${owner}/${repo}`
                }
            };
            return rejected;
        }
        if createdComment is error {
            log:printError("failed to create comment on GitHub", createdComment,
                    owner = owner, repo = repo, issueNumber = issueNumber);
            CommentCreationFailed creationFailed = {
                body: {
                    message: string `Failed to comment on issue ${issueNumber} for ${owner}/${repo}`
                }
            };
            return creationFailed;
        }
        CommentCreated created = {
            body: createdComment
        };
        return created;
    }
}
