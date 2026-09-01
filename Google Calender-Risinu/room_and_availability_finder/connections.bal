import ballerinax/googleapis.gcalendar;

final gcalendar:Client calendarClient = check new ({
    auth: {
        clientId,
        clientSecret,
        refreshToken,
        refreshUrl
    }
});
