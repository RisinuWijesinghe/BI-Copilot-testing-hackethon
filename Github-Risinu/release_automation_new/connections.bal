import ballerinax/github;

configurable string githubToken = ?;
configurable string smokeTestWorkflowFile = "post-release-smoke.yml";
configurable int workflowRunPollMaxAttempts = 60;
configurable decimal workflowRunPollIntervalSeconds = 10;

final github:Client githubClient = check new ({
    auth: {
        token: githubToken
    }
});
