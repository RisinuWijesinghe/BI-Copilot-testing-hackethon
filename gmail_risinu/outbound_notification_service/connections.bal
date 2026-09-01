import ballerinax/googleapis.gmail;

final gmail:Client gmailClient = check new (config = {
    auth: {
        clientId: gmailClientId,
        clientSecret: gmailClientSecret,
        refreshToken: gmailRefreshToken,
        refreshUrl: gmailRefreshUrl
    }
});
