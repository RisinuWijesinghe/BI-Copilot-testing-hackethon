import ballerina/lang.regexp;
import ballerinax/github;

// Conventional commit header pattern: type(optional scope)(optional !): description
final regexp:RegExp conventionalCommitPattern = re `^(feat|fix|perf|chore)(\([^)]*\))?!?:\s*(.*)$`;

// Extracts the first line of a commit message.
function getCommitSubject(string fullMessage) returns string {
    string[] lines = re `\n`.split(fullMessage);
    if lines.length() > 0 {
        return lines[0];
    }
    return fullMessage;
}

// Resolves the author display name for a commit, falling back sensibly when data is missing.
function resolveCommitAuthor(github:Commit gitCommit) returns string {
    github:NullableSimpleUser? commitAuthorAccount = gitCommit.author;
    if commitAuthorAccount is github:NullableSimpleUser {
        return commitAuthorAccount.login;
    }
    github:CommitCommit innerCommit = gitCommit.'commit;
    github:NullableGitUser? rawAuthor = innerCommit.author;
    if rawAuthor is github:NullableGitUser {
        string? rawAuthorName = rawAuthor.name;
        if rawAuthorName is string {
            return rawAuthorName;
        }
    }
    return "unknown";
}

// Builds a changelog grouped by conventional-commit type from a list of commits.
function buildChangelog(github:Commit[] commits) returns Changelog {
    ChangelogEntry[] featEntries = [];
    ChangelogEntry[] fixEntries = [];
    ChangelogEntry[] perfEntries = [];
    ChangelogEntry[] choreEntries = [];
    ChangelogEntry[] otherEntries = [];

    foreach github:Commit gitCommit in commits {
        string commitSha = gitCommit.sha;
        string shortSha = commitSha.length() >= 7 ? commitSha.substring(0, 7) : commitSha;
        github:CommitCommit innerCommit = gitCommit.'commit;
        string fullMessage = innerCommit.message;
        string subject = getCommitSubject(fullMessage);
        string author = resolveCommitAuthor(gitCommit);

        ChangelogEntry entry = {
            shortSha: shortSha,
            message: subject,
            author: author
        };

        regexp:Groups? groups = conventionalCommitPattern.findGroups(subject);
        if groups is regexp:Groups {
            regexp:Span? typeSpan = groups[1];
            string commitType = typeSpan is regexp:Span ? typeSpan.substring() : "";
            regexp:Span? descriptionSpan = groups[3];
            string description = descriptionSpan is regexp:Span ? descriptionSpan.substring() : subject;
            ChangelogEntry conventionalEntry = {
                shortSha: shortSha,
                message: description,
                author: author
            };
            if commitType == "feat" {
                featEntries.push(conventionalEntry);
            } else if commitType == "fix" {
                fixEntries.push(conventionalEntry);
            } else if commitType == "perf" {
                perfEntries.push(conventionalEntry);
            } else if commitType == "chore" {
                choreEntries.push(conventionalEntry);
            } else {
                otherEntries.push(entry);
            }
        } else {
            otherEntries.push(entry);
        }
    }

    return {
        feat: featEntries,
        fix: fixEntries,
        perf: perfEntries,
        chore: choreEntries,
        other: otherEntries
    };
}

// Renders a single changelog section as markdown, returning an empty string when there are no entries.
function renderChangelogSection(string title, ChangelogEntry[] entries) returns string {
    if entries.length() == 0 {
        return "";
    }
    string section = string `## ${title}` + "\n";
    foreach ChangelogEntry entry in entries {
        section += string `- ${entry.message} (${entry.shortSha}) by @${entry.author}` + "\n";
    }
    return section + "\n";
}

// Renders the full changelog as a markdown document to be used as the release body.
function renderChangelog(Changelog changelog) returns string {
    string body = "";
    body += renderChangelogSection("Features", changelog.feat);
    body += renderChangelogSection("Bug Fixes", changelog.fix);
    body += renderChangelogSection("Performance Improvements", changelog.perf);
    body += renderChangelogSection("Chores", changelog.chore);
    body += renderChangelogSection("Other Changes", changelog.other);
    if body == "" {
        return "No changes.";
    }
    return body.trim();
}
