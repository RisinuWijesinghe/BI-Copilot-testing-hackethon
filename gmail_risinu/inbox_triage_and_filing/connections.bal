import ballerinax/googleapis.gmail;

final gmail:Client gmailClient = check initializeGmailClient();

// Isolated in its own function so tests can replace it (via test:Mock) with a
// fake client instead of performing a real OAuth handshake against Gmail.
function initializeGmailClient() returns gmail:Client|error {
    return new (config = {
        auth: {
            clientId: gmailClientId,
            clientSecret: gmailClientSecret,
            refreshToken: gmailRefreshToken,
            refreshUrl: gmailRefreshUrl
        }
    });
}
