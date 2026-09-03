import ballerina/time;

# A single row of the compliance report: one secret tagged as belonging to
# the audited team.
public type SecretAuditEntry record {|
    string secretName;
    # The last time Secrets Manager successfully rotated this secret.
    # Absent when the secret has never been rotated.
    time:Utc? lastRotatedDate;
    boolean rotationEnabled;
|};

# Where a secret lands against the rotation policy.
#
# - HEALTHY: rotation is enabled and it last rotated within the policy window.
# - OVERDUE: rotation is enabled but it last rotated more than 90 days ago.
# - UNMANAGED: rotation is not enabled at all, or it has never rotated even
#   once (no last-rotated timestamp to measure against the policy).
public type RotationPolicyStatus HEALTHY|OVERDUE|UNMANAGED;

public const HEALTHY = "HEALTHY";
public const OVERDUE = "OVERDUE";
public const UNMANAGED = "UNMANAGED";

# A compliance report entry together with its policy classification.
public type ClassifiedSecretAuditEntry record {|
    *SecretAuditEntry;
    RotationPolicyStatus policyStatus;
|};

