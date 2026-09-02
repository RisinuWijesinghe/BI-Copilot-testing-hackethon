import ballerinax/googleapis.gcalendar;

# The Google Calendar client used to reach the calendar service.
# This starts out unset and is constructed lazily on first use, so that tests can pre-populate it with a mock
# (before any business function runs) without ever making a real network call.
gcalendar:Client? calendarClient = ();

# Returns the Google Calendar client, constructing (and caching) the real client on first use.
#
# + return - the calendar client, or an error if it could not be constructed
function getCalendarClient() returns gcalendar:Client|error {
    gcalendar:Client? existingClient = calendarClient;
    if existingClient is gcalendar:Client {
        return existingClient;
    }
    gcalendar:Client newClient = check new ({
        auth: {
            clientId,
            clientSecret,
            refreshToken,
            refreshUrl
        }
    });
    calendarClient = newClient;
    return newClient;
}
