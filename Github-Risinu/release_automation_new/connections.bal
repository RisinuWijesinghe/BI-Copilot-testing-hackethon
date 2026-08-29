import ballerinax/github;

configurable string githubToken = ?;

final github:Client githubClient = check new ({
    auth: {
        token: githubToken
    }
});
