import ballerinax/github;

configurable string githubOrg = ?;
configurable string githubToken = ?;

// Maps a CODEOWNERS path pattern (e.g. "*", "/docs/", "*.js") to the owning GitHub user/team
// (e.g. "@my-org/backend-team"), used to generate a CODEOWNERS file during remediation.
configurable map<string> codeownersTeamMapping = ?;

// Copyright holder name to embed in generated LICENSE files during remediation.
configurable string licenseCopyrightHolder = ?;

final github:Client githubClient = check new ({
    auth: {
        token: githubToken
    }
});
