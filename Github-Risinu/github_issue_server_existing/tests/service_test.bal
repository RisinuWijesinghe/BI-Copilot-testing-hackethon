import ballerinax/github;

import ballerina/http;
import ballerina/test;

final http:Client testClient = check new ("http://localhost:8080");

// The service calls the connector without explicit headers, so argument-matched stubs expect
// the parameter's default value: an empty header map.
final map<string|string[]> noHeaders = {};

# Builds a minimal GitHub `Issue` record for use as a mock response.
#
# + number - Number of the issue
# + title - Title of the issue
# + state - State of the issue
# + login - Login of the issue author
# + labels - Labels attached to the issue
# + return - A `github:Issue` populated with the given values and empty defaults elsewhere
function mockIssue(int number, string title, string state, string login, string[] labels = [])
        returns github:Issue => {
    id: number,
    nodeId: "node",
    url: "https://api.github.com/repos/octocat/hello-world/issues/" + number.toString(),
    repositoryUrl: "https://api.github.com/repos/octocat/hello-world",
    labelsUrl: "https://api.github.com/repos/octocat/hello-world/issues/" + number.toString() + "/labels{/name}",
    commentsUrl: "https://api.github.com/repos/octocat/hello-world/issues/" + number.toString() + "/comments",
    eventsUrl: "https://api.github.com/repos/octocat/hello-world/issues/" + number.toString() + "/events",
    htmlUrl: "https://github.com/octocat/hello-world/issues/" + number.toString(),
    number: number,
    state: state,
    title: title,
    user: {
        login: login,
        id: 1,
        nodeId: "user-node",
        avatarUrl: "",
        gravatarId: (),
        url: "",
        htmlUrl: "",
        followersUrl: "",
        followingUrl: "",
        gistsUrl: "",
        starredUrl: "",
        subscriptionsUrl: "",
        organizationsUrl: "",
        reposUrl: "",
        eventsUrl: "",
        receivedEventsUrl: "",
        'type: "User",
        siteAdmin: false
    },
    labels: from string label in labels
        select label,
    assignee: (),
    milestone: (),
    locked: false,
    comments: 0,
    createdAt: "2024-01-01T00:00:00Z",
    updatedAt: "2024-01-01T00:00:00Z",
    closedAt: (),
    authorAssociation: "OWNER"
};

@test:Config {}
function testGetOpenIssuesWithoutLabel() returns error? {
    github:Client mockGithubClient = test:mock(github:Client);
    github:Issue[] mockIssues = [
        mockIssue(1, "Bug in login", "open", "alice"),
        mockIssue(2, "Feature request", "open", "bob")
    ];
    // Matching on the arguments asserts that no `labels` filter is sent to GitHub when the
    // caller does not supply one; a mismatch leaves the stub unmatched and fails the test.
    github:IssuesListForRepoQueries expectedQueries = {state: "open"};
    test:prepare(mockGithubClient)
        .whenResource("repos/:owner/:repo/issues")
        .onMethod("get")
        .withArguments(noHeaders, expectedQueries)
        .thenReturn(mockIssues);
    githubClient = mockGithubClient;

    IssueSummary[] response = check testClient->/repos/octocat/["hello-world"]/issues();
    test:assertEquals(response.length(), 2, msg = "Expected two open issues");
    test:assertEquals(response[0], {number: 1, title: "Bug in login", state: "open", author: "alice"},
            msg = "First issue did not match expected summary");
}

@test:Config {}
function testGetOpenIssuesWithLabel() returns error? {
    github:Client mockGithubClient = test:mock(github:Client);
    github:Issue[] mockIssues = [
        mockIssue(3, "Crash on start", "open", "carol", labels = ["bug"])
    ];
    // The label filter is applied by GitHub itself, so the assertion that matters is that the
    // label reaches the connector as the `labels` query parameter. Matching on the arguments
    // makes the stub unmatched -- and the test fail -- if the label is ever dropped.
    github:IssuesListForRepoQueries expectedQueries = {state: "open", labels: "bug"};
    test:prepare(mockGithubClient)
        .whenResource("repos/:owner/:repo/issues")
        .onMethod("get")
        .withArguments(noHeaders, expectedQueries)
        .thenReturn(mockIssues);
    githubClient = mockGithubClient;

    IssueSummary[] response = check testClient->/repos/octocat/["hello-world"]/issues(label = "bug");
    test:assertEquals(response.length(), 1, msg = "Expected a single issue carrying the label");
    test:assertEquals(response[0], {number: 3, title: "Crash on start", state: "open", author: "carol"},
            msg = "Issue did not match expected summary");
}

@test:Config {}
function testGetOpenIssuesGithubFailure() returns error? {
    github:Client mockGithubClient = test:mock(github:Client);
    test:prepare(mockGithubClient)
        .whenResource("repos/:owner/:repo/issues")
        .onMethod("get")
        .thenReturn(error("connection failure"));
    githubClient = mockGithubClient;

    http:Response response = check testClient->/repos/octocat/["hello-world"]/issues();
    test:assertEquals(response.statusCode, 500, msg = "Expected a 500 response when GitHub cannot be reached");
}

@test:Config {}
function testCreateIssueSuccess() returns error? {
    github:Client mockGithubClient = test:mock(github:Client);
    test:prepare(mockGithubClient)
        .whenResource("repos/:owner/:repo/issues")
        .onMethod("post")
        .thenReturn(mockIssue(42, "New bug", "open", "dave"));
    githubClient = mockGithubClient;

    NewIssue newIssue = {title: "New bug"};
    http:Response response = check testClient->/repos/octocat/["hello-world"]/issues.post(newIssue);
    test:assertEquals(response.statusCode, 201, msg = "Expected a 201 response for a created issue");
    json responsePayload = check response.getJsonPayload();
    CreatedIssue createdIssue = check responsePayload.fromJsonWithType(CreatedIssue);
    test:assertEquals(createdIssue.number, 42, msg = "Created issue number did not match");
    test:assertEquals(createdIssue.url, "https://github.com/octocat/hello-world/issues/42",
            msg = "Created issue URL did not match");
}

@test:Config {}
function testCreateIssueRejectedByGithub() returns error? {
    github:Client mockGithubClient = test:mock(github:Client);
    test:prepare(mockGithubClient)
        .whenResource("repos/:owner/:repo/issues")
        .onMethod("post")
        .thenReturn(error http:ClientRequestError("Unprocessable Entity",
                statusCode = 422, headers = {}, body = "Validation failed"));
    githubClient = mockGithubClient;

    NewIssue newIssue = {title: ""};
    http:Response response = check testClient->/repos/octocat/["hello-world"]/issues.post(newIssue);
    test:assertEquals(response.statusCode, 422, msg = "Expected a 422 response when GitHub rejects the request");
}

@test:Config {}
function testCreateCommentSuccess() returns error? {
    github:Client mockGithubClient = test:mock(github:Client);
    github:IssueComment mockComment = {
        id: 99,
        nodeId: "comment-node",
        url: "https://api.github.com/repos/octocat/hello-world/issues/comments/99",
        htmlUrl: "https://github.com/octocat/hello-world/issues/1#issuecomment-99",
        issueUrl: "https://api.github.com/repos/octocat/hello-world/issues/1",
        user: (),
        createdAt: "2024-01-01T00:00:00Z",
        updatedAt: "2024-01-01T00:00:00Z",
        authorAssociation: "OWNER"
    };
    test:prepare(mockGithubClient)
        .whenResource("repos/:owner/:repo/issues/:issueNumber/comments")
        .onMethod("post")
        .thenReturn(mockComment);
    githubClient = mockGithubClient;

    NewComment newComment = {body: "Thanks for reporting!"};
    http:Response response = check testClient->/repos/octocat/["hello-world"]/issues/[1]/comments.post(newComment);
    test:assertEquals(response.statusCode, 201, msg = "Expected a 201 response for a created comment");
    json responsePayload = check response.getJsonPayload();
    CreatedComment createdComment = check responsePayload.fromJsonWithType(CreatedComment);
    test:assertEquals(createdComment.id, 99, msg = "Created comment id did not match");
    test:assertEquals(createdComment.url, "https://github.com/octocat/hello-world/issues/1#issuecomment-99",
            msg = "Created comment URL did not match");
}

@test:Config {}
function testCreateCommentRejectedByGithub() returns error? {
    github:Client mockGithubClient = test:mock(github:Client);
    test:prepare(mockGithubClient)
        .whenResource("repos/:owner/:repo/issues/:issueNumber/comments")
        .onMethod("post")
        .thenReturn(error http:ClientRequestError("Unprocessable Entity",
                statusCode = 422, headers = {}, body = "Validation failed"));
    githubClient = mockGithubClient;

    NewComment newComment = {body: ""};
    http:Response response = check testClient->/repos/octocat/["hello-world"]/issues/[1]/comments.post(newComment);
    test:assertEquals(response.statusCode, 422, msg = "Expected a 422 response when GitHub rejects the comment");
}
