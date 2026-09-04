// AWS region the secret store lives in.
configurable string awsRegion = "us-east-1";

// Web identity (OIDC) configuration used to obtain temporary credentials via
// AWS STS. This is the standard mechanism for workloads running on EKS
// (IRSA) or CI/CD systems that issue an OIDC token, so no long-lived AWS
// keys need to be stored with this tool.
configurable string webIdentityRoleArn = ?;
configurable string webIdentityTokenFile = ?;

// The fixed list of secret names/IDs to audit, handed to us explicitly by
// compliance. Tag-based discovery was dropped since tagging conventions
// turned out to be inconsistent across teams.
configurable string[] auditedSecretIds = ?;

// Rotation policy: a secret that has rotation enabled but hasn't rotated
// within this many days is flagged as overdue.
configurable int rotationPolicyMaxAgeDays = 90;

