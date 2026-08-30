import ballerinax/github;

# Personal access token used to call the GitHub REST API.
configurable string githubToken = ?;

github:Client githubClient = check new ({
    auth: {
        token: githubToken
    }
});

# The subset of a GitHub issue exposed by this service.
#
# + number - Number uniquely identifying the issue within its repository
# + title - Title of the issue
# + state - State of the issue; either `open` or `closed`
# + author - Login of the user who created the issue
public type IssueSummary record {|
    int number;
    string title;
    string state;
    string author;
|};

# Fetches the open issues of a repository from GitHub.
#
# Pull requests are dropped, since the GitHub REST API reports them as issues. When a label is provided,
# only issues carrying that label are returned.
#
# + owner - Account owner of the repository
# + repo - Name of the repository
# + label - Label to filter the issues by
# + return - The open issues of the repository, or an error if the call fails
function getOpenIssues(string owner, string repo, string? label) returns IssueSummary[]|error {
    github:Issue[] issues;
    if label is string {
        issues = check githubClient->/repos/[owner]/[repo]/issues(state = "open", labels = label);
    } else {
        issues = check githubClient->/repos/[owner]/[repo]/issues(state = "open");
    }
    return from github:Issue issue in issues
        where issue?.pullRequest is ()
        select {
            number: issue.number,
            title: issue.title,
            state: issue.state,
            author: issue.user?.login ?: ""
        };
}

# Details required to file a new issue on GitHub.
#
# + title - Title of the issue
# + body - Body content of the issue
# + labels - Labels to associate with the issue
# + assignees - Logins of the users to assign to the issue
public type NewIssue record {|
    string title;
    string body?;
    string[] labels?;
    string[] assignees?;
|};

# Identifying information of a newly created issue.
#
# + number - Number uniquely identifying the issue within its repository
# + url - Browser URL of the created issue
public type CreatedIssue record {|
    int number;
    string url;
|};

# Creates a new issue on GitHub.
#
# + owner - Account owner of the repository
# + repo - Name of the repository
# + newIssue - Details of the issue to create
# + return - The identifying information of the created issue, an `http:ClientRequestError` if GitHub rejected the
# request (e.g. validation failure), or another error if the call otherwise fails
function createIssue(string owner, string repo, NewIssue newIssue) returns CreatedIssue|error {
    github:RepoIssuesBody payload = {
        title: newIssue.title,
        body: newIssue?.body,
        labels: newIssue?.labels,
        assignees: newIssue?.assignees
    };
    github:Issue createdIssue = check githubClient->/repos/[owner]/[repo]/issues.post(payload);
    return {
        number: createdIssue.number,
        url: createdIssue.htmlUrl
    };
}

# Details required to post a comment on an existing issue.
#
# + body - Body content of the comment
public type NewComment record {|
    string body;
|};

# Identifying information of a newly created comment.
#
# + id - Number uniquely identifying the comment within its repository
# + url - Browser URL of the created comment
public type CreatedComment record {|
    int id;
    string url;
|};

# Posts a comment on an existing GitHub issue.
#
# + owner - Account owner of the repository
# + repo - Name of the repository
# + issueNumber - Number of the issue to comment on
# + newComment - Details of the comment to create
# + return - The identifying information of the created comment, an `http:ClientRequestError` if GitHub rejected the
# request (e.g. validation failure), or another error if the call otherwise fails
function createComment(string owner, string repo, int issueNumber, NewComment newComment)
        returns CreatedComment|error {
    github:IssueComment createdComment =
        check githubClient->/repos/[owner]/[repo]/issues/[issueNumber]/comments.post({body: newComment.body});
    return {
        id: createdComment.id,
        url: createdComment.htmlUrl
    };
}
