import ballerina/time;
import ballerinax/aws.secretmanager;

# Builds one audit entry per secret in the fixed, explicitly supplied list
# by describing it for its rotation status and last-rotated date. Secret
# values are never fetched here - only metadata. Each entry is classified
# against the rotation policy so the report can be split into
# healthy/overdue/unmanaged groups.
function buildAuditReport() returns ClassifiedSecretAuditEntry[]|secretmanager:Error {
    ClassifiedSecretAuditEntry[] auditEntries = [];
    foreach string secretId in auditedSecretIds {
        secretmanager:DescribeSecretResponse secretDetails = check secretManagerClient->describeSecret(secretId);
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

