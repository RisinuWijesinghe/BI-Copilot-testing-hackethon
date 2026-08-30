// Request payload for cutting a new release
public type CutReleaseRequest record {|
    string owner;
    string repo;
    string version;
    string targetBranch = "main";
    string artifactPath;
|};

// A single commit entry included in the changelog
public type ChangelogEntry record {|
    string shortSha;
    string message;
    string author;
|};

// Changelog grouped by conventional-commit type
public type Changelog record {|
    ChangelogEntry[] feat;
    ChangelogEntry[] fix;
    ChangelogEntry[] perf;
    ChangelogEntry[] chore;
    ChangelogEntry[] other;
|};

// Successful response returned once the release has been cut
public type CutReleaseResponse record {|
    string tagName;
    string previousTagName;
    string releaseUrl;
    string releaseHtmlUrl;
    boolean draft;
    string changelogBody;
    string smokeTestWorkflowRunUrl;
|};

// Error response returned when the release cannot be cut
public type CutReleaseError record {|
    string message;
|};
