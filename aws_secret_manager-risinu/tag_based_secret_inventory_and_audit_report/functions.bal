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
# here - only metadata.
function buildTeamAuditReport() returns SecretAuditEntry[]|secretmanager:Error {
    string[] secretArns = check discoverTeamTaggedSecretArns();

    SecretAuditEntry[] auditEntries = [];
    foreach string secretArn in secretArns {
        secretmanager:DescribeSecretResponse secretDetails = check secretManagerClient->describeSecret(secretArn);
        auditEntries.push({
            secretName: secretDetails.name,
            lastRotatedDate: secretDetails.lastRotatedDate,
            rotationEnabled: secretDetails.rotationEnabled
        });
    }

    return auditEntries;
}

