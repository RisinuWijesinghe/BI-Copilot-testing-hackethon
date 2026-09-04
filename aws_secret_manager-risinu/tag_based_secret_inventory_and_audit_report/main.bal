import ballerina/io;
import ballerina/time;

public function main() {
    ClassifiedSecretAuditEntry[]|error auditEntries = buildAuditReport();

    if auditEntries is error {
        io:println(string `Failed to generate secret compliance report: could not read from the secret store (check credentials and connectivity). Details: ${auditEntries.message()}`);
        return;
    }

    io:println("Secret compliance report");
    io:println(string `Total secrets audited: ${auditEntries.length()}`);
    io:println("----------------------------------------------------------------");

    if auditEntries.length() == 0 {
        io:println("No secret IDs were configured for audit.");
        return;
    }

    ClassifiedSecretAuditEntry[] healthyEntries = from ClassifiedSecretAuditEntry entry in auditEntries
        where entry.policyStatus == HEALTHY
        select entry;
    ClassifiedSecretAuditEntry[] overdueEntries = from ClassifiedSecretAuditEntry entry in auditEntries
        where entry.policyStatus == OVERDUE
        select entry;
    ClassifiedSecretAuditEntry[] unmanagedEntries = from ClassifiedSecretAuditEntry entry in auditEntries
        where entry.policyStatus == UNMANAGED
        select entry;

    printGroup(string `HEALTHY (rotated within ${rotationPolicyMaxAgeDays} days) - ${healthyEntries.length()}`, healthyEntries);
    printGroup(string `OVERDUE (rotation enabled but not rotated within ${rotationPolicyMaxAgeDays} days) - ${overdueEntries.length()}`, overdueEntries);
    printGroup(string `UNMANAGED (rotation disabled or never rotated) - ${unmanagedEntries.length()}`, unmanagedEntries);
}

# Prints one section of the report: a title followed by every entry in that
# group, or a placeholder line when the group is empty.
function printGroup(string title, ClassifiedSecretAuditEntry[] entries) {
    io:println();
    io:println(string `=== ${title} ===`);

    if entries.length() == 0 {
        io:println("  (none)");
        return;
    }

    foreach ClassifiedSecretAuditEntry entry in entries {
        string lastRotatedText = "never rotated";
        time:Utc? lastRotatedDate = entry.lastRotatedDate;
        if lastRotatedDate is time:Utc {
            lastRotatedText = time:utcToString(lastRotatedDate);
        }

        string rotationStatusText = entry.rotationEnabled ? "enabled" : "disabled";

        io:println(string `  Secret: ${entry.secretName}`);
        io:println(string `    Last rotated: ${lastRotatedText}`);
        io:println(string `    Rotation enabled: ${rotationStatusText}`);
    }
}

