import ballerina/time;
import ballerinax/aws.secretmanager;

# Discovers every secret ARN tagged as belonging to the configured team.
#
# The secret store can return results a page at a time, so this keeps
# calling for the next page (following `nextToken`) until the store reports
# there are no more pages left - it never assumes the first page is the
# whole answer.
#
# This only ever looks at secret metadata (names/ARNs and the pagination
# token); the encrypted secret contents returned alongside them are never
# read or reported on.
function discoverTeamTaggedSecretArns() returns string[]|secretmanager:Error {
    string[] secretArns = [];
    string? nextToken = ();
    boolean hasMorePages = true;

    while hasMorePages {
        secretmanager:BatchGetSecretValueResponse response = check secretManagerClient->batchGetSecretValue(
            filters = [
                {'key: "tag-key", values: [teamTagKey]},
                {'key: "tag-value", values: [teamTagValue]}
            ],
            maxResults = 20,
            nextToken = nextToken ?: ""
        );

        secretmanager:SecretValue[]? secretValues = response.secretValues;
        if secretValues is secretmanager:SecretValue[] {
            foreach secretmanager:SecretValue secretValue in secretValues {
                secretArns.push(secretValue.arn);
            }
        }

        nextToken = response.nextToken;
        hasMorePages = nextToken is string;
    }

    return secretArns;
}

# Builds one audit entry per tagged secret by describing it for its
# rotation status and last-rotated date. Secret values are never fetched
# here - only metadata. Each entry is classified against the rotation
# policy so the report can be split into healthy/overdue/unmanaged groups.
function buildTeamAuditReport() returns ClassifiedSecretAuditEntry[]|secretmanager:Error {
    string[] secretArns = check discoverTeamTaggedSecretArns();

    ClassifiedSecretAuditEntry[] auditEntries = [];
    foreach string secretArn in secretArns {
        secretmanager:DescribeSecretResponse secretDetails = check secretManagerClient->describeSecret(secretArn);
        SecretAuditEntry auditEntry = {
            secretName: secretDetails.name,
            lastRotatedDate: secretDetails.lastRotatedDate,
            rotationEnabled: secretDetails.rotationEnabled
        };
        auditEntries.push({
            ...auditEntry,
            policyStatus: classifyRotationStatus(auditEntry)
        });
    }

    return auditEntries;
}

# Classifies a secret against the rotation policy.
#
# - Rotation not enabled at all -> UNMANAGED, regardless of any timestamp.
# - Rotation enabled but it has never actually rotated (no last-rotated
#   timestamp) -> UNMANAGED, since there is nothing to measure against the
#   policy window.
# - Rotation enabled and last rotated more than the policy's max age ago ->
#   OVERDUE.
# - Otherwise -> HEALTHY.
function classifyRotationStatus(SecretAuditEntry auditEntry) returns RotationPolicyStatus {
    if !auditEntry.rotationEnabled {
        return UNMANAGED;
    }

    time:Utc? lastRotatedDate = auditEntry.lastRotatedDate;
    if lastRotatedDate is () {
        return UNMANAGED;
    }

    time:Utc policyThreshold = time:utcAddSeconds(time:utcNow(), -(<decimal>rotationPolicyMaxAgeDays * 86400));
    if lastRotatedDate < policyThreshold {
        return OVERDUE;
    }

    return HEALTHY;
}

