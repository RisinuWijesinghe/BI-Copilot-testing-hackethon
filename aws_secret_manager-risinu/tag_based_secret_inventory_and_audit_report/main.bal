import ballerina/io;
import ballerina/time;

public function main() {
    SecretAuditEntry[]|error auditEntries = buildTeamAuditReport();

    if auditEntries is error {
        io:println(string `Failed to generate secret compliance report: could not read from the secret store (check credentials and connectivity). Details: ${auditEntries.message()}`);
        return;
    }

    io:println(string `Secret compliance report for team "${teamTagValue}"`);
    io:println(string `Total secrets found: ${auditEntries.length()}`);
    io:println("----------------------------------------------------------------");

    if auditEntries.length() == 0 {
        io:println("No secrets are tagged for this team.");
        return;
    }

    foreach SecretAuditEntry entry in auditEntries {
        string lastRotatedText = "never rotated";
        time:Utc? lastRotatedDate = entry.lastRotatedDate;
        if lastRotatedDate is time:Utc {
            lastRotatedText = time:utcToString(lastRotatedDate);
        }

        string rotationStatusText = entry.rotationEnabled ? "enabled" : "disabled";

        io:println(string `Secret: ${entry.secretName}`);
        io:println(string `  Last rotated: ${lastRotatedText}`);
        io:println(string `  Rotation enabled: ${rotationStatusText}`);
    }
}

