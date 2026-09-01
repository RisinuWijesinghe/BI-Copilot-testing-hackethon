import ballerinax/googleapis.calendar;

// Test double for `CalendarService` that never reaches Google. Behavior is configured
// per test via the public fields before it is installed as `googleCalendarClient`.
public class MockCalendarService {
    *CalendarService;

    // When set, every operation below returns this error instead of its normal result.
    public error? failureToReturn = ();

    // Calendars known to this stand-in. Absence of a requested calendar id simulates a 404.
    public map<boolean> knownCalendarIds = {"primary": true};

    // Events known to this stand-in, keyed by "calendarId/eventId". Absence of a
    // requested event simulates a 404.
    public map<calendar:Event> knownEvents = {};

    // Events to return from `getEvents` for a given calendar id.
    public map<calendar:Event[]> agendaByCalendarId = {};

    // Sequence used to generate unique identifiers for created resources.
    private int sequence = 0;

    private function nextId(string prefix) returns string {
        self.sequence += 1;
        return string `${prefix}-${self.sequence}`;
    }

    public function createCalendar(string title) returns calendar:CalendarResource|error {
        error? failure = self.failureToReturn;
        if failure is error {
            return failure;
        }
        string calendarId = self.nextId("calendar");
        self.knownCalendarIds[calendarId] = true;
        return {
            kind: "calendar#calendar",
            etag: "etag",
            id: calendarId,
            summary: title,
            timeZone: "UTC",
            conferenceProperties: {allowedConferenceSolutionTypes: []}
        };
    }

    public function createEvent(string calendarId, calendar:InputEvent event) returns calendar:Event|error {
        error? failure = self.failureToReturn;
        if failure is error {
            return failure;
        }
        if !self.knownCalendarIds.hasKey(calendarId) {
            return error(string `Calendar '${calendarId}' not found`, statusCode = 404);
        }
        string eventId = self.nextId("event");
        calendar:Event createdEvent = {
            kind: "calendar#event",
            etag: "etag",
            id: eventId,
            status: "confirmed",
            htmlLink: string `https://calendar.google.com/event?eid=${eventId}`,
            summary: event.summary,
            description: event.description,
            location: event.location,
            'start: event.'start,
            end: event.end,
            attendees: event.attendees
        };
        self.knownEvents[string `${calendarId}/${eventId}`] = createdEvent;
        return createdEvent;
    }

    public function getEvent(string calendarId, string eventId) returns calendar:Event|error {
        error? failure = self.failureToReturn;
        if failure is error {
            return failure;
        }
        calendar:Event? existingEvent = self.knownEvents[string `${calendarId}/${eventId}`];
        if existingEvent is () {
            return error(string `Event '${eventId}' not found`, statusCode = 404);
        }
        return existingEvent;
    }

    public function getEvents(string calendarId, calendar:EventFilterCriteria filter) returns stream<calendar:Event, error?>|error {
        error? failure = self.failureToReturn;
        if failure is error {
            return failure;
        }
        if !self.knownCalendarIds.hasKey(calendarId) {
            return error(string `Calendar '${calendarId}' not found`, statusCode = 404);
        }
        calendar:Event[] agendaEvents = self.agendaByCalendarId[calendarId] ?: [];
        return agendaEvents.toStream();
    }

    public function updateEvent(string calendarId, string eventId, calendar:InputEvent event, calendar:EventsToAccess optional) returns calendar:Event|error {
        error? failure = self.failureToReturn;
        if failure is error {
            return failure;
        }
        string key = string `${calendarId}/${eventId}`;
        calendar:Event? existingEvent = self.knownEvents[key];
        if existingEvent is () {
            return error(string `Event '${eventId}' not found`, statusCode = 404);
        }
        calendar:Event updatedEvent = {
            kind: existingEvent.kind,
            etag: existingEvent.etag,
            id: existingEvent.id,
            status: existingEvent.status,
            htmlLink: existingEvent.htmlLink,
            summary: event.summary,
            description: event.description,
            location: event.location,
            'start: event.'start,
            end: event.end,
            attendees: event.attendees
        };
        self.knownEvents[key] = updatedEvent;
        return updatedEvent;
    }

    public function deleteEvent(string calendarId, string eventId) returns error? {
        error? failure = self.failureToReturn;
        if failure is error {
            return failure;
        }
        string key = string `${calendarId}/${eventId}`;
        calendar:Event? existingEvent = self.knownEvents[key];
        if existingEvent is () {
            return error(string `Event '${eventId}' not found`, statusCode = 404);
        }
        _ = self.knownEvents.remove(key);
        return ();
    }
}
