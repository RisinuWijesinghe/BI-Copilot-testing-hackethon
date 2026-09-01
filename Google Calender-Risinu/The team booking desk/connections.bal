import ballerinax/googleapis.calendar;

final calendar:Client googleCalendarClient = check new ({
    auth: {
        clientId: googleClientId,
        clientSecret: googleClientSecret,
        refreshToken: googleRefreshToken,
        refreshUrl: googleRefreshUrl
    }
});
