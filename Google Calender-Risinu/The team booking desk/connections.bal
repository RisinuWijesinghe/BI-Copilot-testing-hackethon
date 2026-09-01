import ballerinax/googleapis.calendar;

// Abstraction over the Google Calendar operations this service depends on, so that
// tests can substitute a stand-in and never reach Google over the network.
public type CalendarService object {
    public function createCalendar(string title) returns calendar:CalendarResource|error;
    public function createEvent(string calendarId, calendar:InputEvent event) returns calendar:Event|error;
    public function getEvent(string calendarId, string eventId) returns calendar:Event|error;
    public function getEvents(string calendarId, calendar:EventFilterCriteria filter) returns stream<calendar:Event, error?>|error;
    public function updateEvent(string calendarId, string eventId, calendar:InputEvent event, calendar:EventsToAccess optional) returns calendar:Event|error;
    public function deleteEvent(string calendarId, string eventId) returns error?;
};

// Real implementation of `CalendarService`, delegating to the Google Calendar connector.
public class GoogleCalendarService {
    *CalendarService;

    private final calendar:Client calendarClient;

    public function init(calendar:ConnectionConfig config) returns error? {
        self.calendarClient = check new (config);
    }

    public function createCalendar(string title) returns calendar:CalendarResource|error {
        return self.calendarClient->createCalendar(title);
    }

    public function createEvent(string calendarId, calendar:InputEvent event) returns calendar:Event|error {
        return self.calendarClient->createEvent(calendarId, event);
    }

    public function getEvent(string calendarId, string eventId) returns calendar:Event|error {
        return self.calendarClient->getEvent(calendarId, eventId);
    }

    public function getEvents(string calendarId, calendar:EventFilterCriteria filter) returns stream<calendar:Event, error?>|error {
        return self.calendarClient->getEvents(calendarId, filter);
    }

    public function updateEvent(string calendarId, string eventId, calendar:InputEvent event, calendar:EventsToAccess optional) returns calendar:Event|error {
        return self.calendarClient->updateEvent(calendarId, eventId, event, optional);
    }

    public function deleteEvent(string calendarId, string eventId) returns error? {
        return self.calendarClient->deleteEvent(calendarId, eventId);
    }
}

// Module-level calendar service used by the HTTP resources. Not `final` and left
// unset at module load so tests can install a stand-in before the real Google-backed
// client is ever constructed, and so no attempt is made to reach Google's OAuth2
// endpoint (which happens eagerly on client construction) outside of real requests.
CalendarService? googleCalendarClient = ();

// Lazily constructs (once) and returns the real Google-backed calendar service,
// or the stand-in installed by a test if one has already been set.
function getCalendarClient() returns CalendarService|error {
    CalendarService? existingClient = googleCalendarClient;
    if existingClient is CalendarService {
        return existingClient;
    }
    CalendarService newClient = check new GoogleCalendarService({
        auth: {
            clientId: googleClientId,
            clientSecret: googleClientSecret,
            refreshToken: googleRefreshToken,
            refreshUrl: googleRefreshUrl
        }
    });
    googleCalendarClient = newClient;
    return newClient;
}
