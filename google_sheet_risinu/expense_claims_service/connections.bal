import ballerinax/googleapis.sheets;

final sheets:Client sheetsClient = check initializeSheetsClient();

# Builds the Google Sheets client. Extracted into its own function so tests can substitute a mock
# client without triggering the real OAuth2 handshake that happens during client construction.
#
# + return - the configured Google Sheets client, or an `error` if construction fails
function initializeSheetsClient() returns sheets:Client|error {
    return new ({
        auth: {
            clientId,
            clientSecret,
            refreshToken,
            refreshUrl
        }
    });
}
