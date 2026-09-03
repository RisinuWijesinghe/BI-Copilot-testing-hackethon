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

