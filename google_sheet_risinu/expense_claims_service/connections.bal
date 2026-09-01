import ballerinax/googleapis.sheets;

final sheets:Client sheetsClient = check new ({
    auth: {
        clientId,
        clientSecret,
        refreshToken,
        refreshUrl
    }
});
