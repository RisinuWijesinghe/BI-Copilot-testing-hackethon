import ballerina/test;
import ballerina/time;

function buildAuditEntry(string secretName, boolean rotationEnabled, time:Utc? lastRotatedDate) returns SecretAuditEntry => {
    secretName,
    rotationEnabled,
    lastRotatedDate
};

@test:Config {}
function testHealthyWhenRotationEnabledAndRecentlyRotated() {
    time:Utc recentlyRotated = time:utcAddSeconds(time:utcNow(), -60 * 60 * 24 * 10.0d); // 10 days ago
    SecretAuditEntry auditEntry = buildAuditEntry("healthy-secret", true, recentlyRotated);

    RotationPolicyStatus policyStatus = classifyRotationStatus(auditEntry);

    test:assertEquals(policyStatus, HEALTHY, msg = "A secret rotated well within the policy window should be HEALTHY");
}

@test:Config {}
function testHealthyWhenRotationEnabledAndRotatedExactlyAtWindowBoundary() {
    // Just inside the boundary (a few seconds under the max age) should still be healthy.
    time:Utc justInsideWindow = time:utcAddSeconds(time:utcNow(), -(<decimal>rotationPolicyMaxAgeDays * 86400 - 60.0d));
    SecretAuditEntry auditEntry = buildAuditEntry("boundary-secret", true, justInsideWindow);

    RotationPolicyStatus policyStatus = classifyRotationStatus(auditEntry);

    test:assertEquals(policyStatus, HEALTHY, msg = "A secret rotated just inside the policy window should be HEALTHY");
}

@test:Config {}
function testOverdueWhenRotationEnabledButNotRotatedWithinPolicyWindow() {
    time:Utc longAgo = time:utcAddSeconds(time:utcNow(), -60 * 60 * 24 * 120.0d); // 120 days ago
    SecretAuditEntry auditEntry = buildAuditEntry("overdue-secret", true, longAgo);

    RotationPolicyStatus policyStatus = classifyRotationStatus(auditEntry);

    test:assertEquals(policyStatus, OVERDUE, msg = "A secret rotated more than the policy's max age ago should be OVERDUE");
}

@test:Config {}
function testUnmanagedWhenRotationDisabledRegardlessOfLastRotatedDate() {
    time:Utc recentlyRotated = time:utcAddSeconds(time:utcNow(), -60 * 60 * 24 * 1.0d); // 1 day ago
    SecretAuditEntry auditEntry = buildAuditEntry("disabled-secret", false, recentlyRotated);

    RotationPolicyStatus policyStatus = classifyRotationStatus(auditEntry);

    test:assertEquals(policyStatus, UNMANAGED, msg = "A secret with rotation disabled should be UNMANAGED even if it was recently rotated");
}

@test:Config {}
function testUnmanagedWhenRotationEnabledButNeverRotated() {
    SecretAuditEntry auditEntry = buildAuditEntry("never-rotated-secret", true, ());

    RotationPolicyStatus policyStatus = classifyRotationStatus(auditEntry);

    test:assertEquals(policyStatus, UNMANAGED, msg = "A secret with rotation enabled but no last-rotated timestamp should be UNMANAGED, not crash or be skipped");
}

@test:Config {}
function testUnmanagedWhenRotationDisabledAndNeverRotated() {
    SecretAuditEntry auditEntry = buildAuditEntry("fully-unmanaged-secret", false, ());

    RotationPolicyStatus policyStatus = classifyRotationStatus(auditEntry);

    test:assertEquals(policyStatus, UNMANAGED, msg = "A secret with rotation disabled and no last-rotated timestamp should be UNMANAGED");
}
