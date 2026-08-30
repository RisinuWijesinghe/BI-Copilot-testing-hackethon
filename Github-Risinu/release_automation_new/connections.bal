import ballerinax/github;

configurable string githubToken = ?;
configurable string smokeTestWorkflowFile = "post-release-smoke.yml";
configurable string releaseManagerGithubUsername = ?;
configurable decimal smokeTestTimeoutSeconds = 600;
configurable decimal workflowRunPollInitialIntervalSeconds = 5;
configurable decimal workflowRunPollMaxIntervalSeconds = 60;
configurable decimal workflowRunPollBackOffFactor = 2.0;

final github:Client githubClient = check new ({
    auth: {
        token: githubToken
    }
});

// In-memory idempotency cache keyed by "owner/repo/tagName" holding the terminal outcome of a
// /releases/cut invocation, so that client retries with the same version do not repeat side effects.
isolated map<CutReleaseOutcome> releaseCutOutcomes = {};

// Returns the cached outcome for the given idempotency key, if one has already been recorded.
isolated function getCachedOutcome(string idempotencyKey) returns CutReleaseOutcome? {
    lock {
        CutReleaseOutcome? outcome = releaseCutOutcomes[idempotencyKey];
        return outcome.clone();
    }
}

// Records the terminal outcome for the given idempotency key.
isolated function cacheOutcome(string idempotencyKey, CutReleaseOutcome outcome) {
    lock {
        releaseCutOutcomes[idempotencyKey] = outcome.clone();
    }
}
