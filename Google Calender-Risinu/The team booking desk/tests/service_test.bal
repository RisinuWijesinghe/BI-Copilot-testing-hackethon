import ballerina/http;
import ballerina/test;
import ballerina/time;
import ballerinax/googleapis.calendar;

final http:Client testClient = check new (string `http://localhost:${servicePort}/calendar`);

// Installs a fresh mock calendar service before each test so that no test can reach
// Google over the network and no test leaks state into another.
function newMockCalendarService() returns MockCalendarService {
    MockCalendarService mockService = new;
    return mockService;
}

function futureIsoTime(int daysFromNow) returns string {
    time:Utc futureUtc = time:utcAddSeconds(time:utcNow(), <decimal>daysFromNow * 86400);
    time:Civil futureCivil = time:utcToCivil(futureUtc);
    return checkpanic time:civilToString(futureCivil);
}

// ----------------------------------------------------------------------------------
// Happy path: booking
// ----------------------------------------------------------------------------------
@test:Config {}
function testBookMeetingHappyPath() returns error? {
    googleCalendarClient = newMockCalendarService();

    BookMeetingRequest request = {
        title: "Sprint planning",
        description: "Plan the next sprint",
        startTime: futureIsoTime(1),
        endTime: futureIsoTime(2),
        timeZone: "UTC",
        attendees: ["alice@example.com", "bob@example.com"]
    };
    http:Response response = check testClient->post("/calendars/primary/meetings", request);
    test:assertEquals(response.statusCode, 201);

    json responsePayload = check response.getJsonPayload();
    BookMeetingResponse bookingResult = check responsePayload.cloneWithType();
    test:assertTrue(bookingResult.eventId.startsWith("event-"));
    test:assertTrue(bookingResult.eventLink.startsWith("https://calendar.google.com/"));
}

// ----------------------------------------------------------------------------------
// Happy path: agenda
// ----------------------------------------------------------------------------------
@test:Config {}
function testAgendaHappyPath() returns error? {
    MockCalendarService mockService = newMockCalendarService();
    calendar:Event agendaEvent = {
        kind: "calendar#event",
        etag: "etag",
        id: "event-100",
        status: "confirmed",
        summary: "Design review",
        description: "Review the new design",
        location: "Room 42",
        'start: {dateTime: futureIsoTime(1)},
        end: {dateTime: futureIsoTime(1)},
        attendees: [{email: "carol@example.com"}]
    };
    mockService.agendaByCalendarId["primary"] = [agendaEvent];
    googleCalendarClient = mockService;

    http:Response response = check testClient->get(string `/calendars/primary/agenda?startTime=${futureIsoTime(0)}&endTime=${futureIsoTime(5)}`);
    test:assertEquals(response.statusCode, 200);

    json responsePayload = check response.getJsonPayload();
    AgendaItem[] agenda = check responsePayload.cloneWithType();
    test:assertEquals(agenda.length(), 1);
    test:assertEquals(agenda[0].title, "Design review");
    test:assertEquals(agenda[0].location, "Room 42");
    test:assertEquals(agenda[0].attendees, ["carol@example.com"]);
}

// A range with nothing in it is an empty agenda, not an error.
@test:Config {}
function testAgendaEmptyRangeReturnsEmptyList() returns error? {
    googleCalendarClient = newMockCalendarService();

    http:Response response = check testClient->get(string `/calendars/primary/agenda?startTime=${futureIsoTime(0)}&endTime=${futureIsoTime(5)}`);
    test:assertEquals(response.statusCode, 200);

    json responsePayload = check response.getJsonPayload();
    AgendaItem[] agenda = check responsePayload.cloneWithType();
    test:assertEquals(agenda.length(), 0);
}

// Search filters down to only the entries that match title, description, location, or an attendee.
@test:Config {}
function testAgendaSearchFiltersMatchingEntries() returns error? {
    MockCalendarService mockService = newMockCalendarService();
    calendar:Event matchingEvent = {
        kind: "calendar#event",
        etag: "etag",
        id: "event-200",
        status: "confirmed",
        summary: "Budget review",
        'start: {dateTime: futureIsoTime(1)},
        end: {dateTime: futureIsoTime(1)},
        attendees: []
    };
    calendar:Event nonMatchingEvent = {
        kind: "calendar#event",
        etag: "etag",
        id: "event-201",
        status: "confirmed",
        summary: "Standup",
        'start: {dateTime: futureIsoTime(1)},
        end: {dateTime: futureIsoTime(1)},
        attendees: []
    };
    mockService.agendaByCalendarId["primary"] = [matchingEvent, nonMatchingEvent];
    googleCalendarClient = mockService;

    http:Response response = check testClient->get(string `/calendars/primary/agenda?startTime=${futureIsoTime(0)}&endTime=${futureIsoTime(5)}&search=budget`);
    test:assertEquals(response.statusCode, 200);

    json responsePayload = check response.getJsonPayload();
    AgendaItem[] agenda = check responsePayload.cloneWithType();
    test:assertEquals(agenda.length(), 1);
    test:assertEquals(agenda[0].title, "Budget review");
}

// ----------------------------------------------------------------------------------
// Happy path: cancel, including the double-cancel idempotency guarantee
// ----------------------------------------------------------------------------------
@test:Config {}
function testCancelMeetingHappyPath() returns error? {
    MockCalendarService mockService = newMockCalendarService();
    mockService.knownEvents["primary/event-1"] = {
        kind: "calendar#event",
        etag: "etag",
        id: "event-1",
        status: "confirmed",
        summary: "One-on-one",
        'start: {dateTime: futureIsoTime(1)},
        end: {dateTime: futureIsoTime(1)},
        attendees: []
    };
    googleCalendarClient = mockService;

    http:Response firstResponse = check testClient->delete("/calendars/primary/meetings/event-1");
    test:assertEquals(firstResponse.statusCode, 200);
    json firstResponsePayload = check firstResponse.getJsonPayload();
    CancelMeetingResponse firstResult = check firstResponsePayload.cloneWithType();
    test:assertEquals(firstResult.message, "The meeting has been cancelled.");
}

@test:Config {}
function testDoubleCancelStaysSuccessful() returns error? {
    MockCalendarService mockService = newMockCalendarService();
    mockService.knownEvents["primary/event-2"] = {
        kind: "calendar#event",
        etag: "etag",
        id: "event-2",
        status: "confirmed",
        summary: "Retro",
        'start: {dateTime: futureIsoTime(1)},
        end: {dateTime: futureIsoTime(1)},
        attendees: []
    };
    googleCalendarClient = mockService;

    http:Response firstResponse = check testClient->delete("/calendars/primary/meetings/event-2");
    test:assertEquals(firstResponse.statusCode, 200);

    // Second call: the event is already gone from the mock's records, simulating
    // Google returning a not-found for an already-cancelled meeting.
    http:Response secondResponse = check testClient->delete("/calendars/primary/meetings/event-2");
    test:assertEquals(secondResponse.statusCode, 200);
    json secondResponsePayload = check secondResponse.getJsonPayload();
    CancelMeetingResponse secondResult = check secondResponsePayload.cloneWithType();
    test:assertEquals(secondResult.message, "The meeting has been cancelled.");
}

// ----------------------------------------------------------------------------------
// Validation rejections
// ----------------------------------------------------------------------------------
@test:Config {}
function testBookMeetingRejectsEndNotAfterStart() returns error? {
    googleCalendarClient = newMockCalendarService();

    BookMeetingRequest request = {
        title: "Bad meeting",
        startTime: futureIsoTime(2),
        endTime: futureIsoTime(1),
        timeZone: "UTC",
        attendees: []
    };
    http:Response response = check testClient->post("/calendars/primary/meetings", request);
    test:assertEquals(response.statusCode, 400);

    json responsePayload = check response.getJsonPayload();
    ErrorDetails errorResult = check responsePayload.cloneWithType();
    test:assertEquals(errorResult.message, "The meeting end time must be after the start time.");
}

@test:Config {}
function testBookMeetingRejectsStartInThePast() returns error? {
    googleCalendarClient = newMockCalendarService();

    BookMeetingRequest request = {
        title: "Bad meeting",
        startTime: futureIsoTime(-2),
        endTime: futureIsoTime(-1),
        timeZone: "UTC",
        attendees: []
    };
    http:Response response = check testClient->post("/calendars/primary/meetings", request);
    test:assertEquals(response.statusCode, 400);

    json responsePayload = check response.getJsonPayload();
    ErrorDetails errorResult = check responsePayload.cloneWithType();
    test:assertEquals(errorResult.message, "The meeting start time must not be in the past.");
}

@test:Config {}
function testCreateCalendarRejectsEmptyName() returns error? {
    googleCalendarClient = newMockCalendarService();

    CreateCalendarRequest request = {calendarName: "   "};
    http:Response response = check testClient->post("/calendars", request);
    test:assertEquals(response.statusCode, 400);

    json responsePayload = check response.getJsonPayload();
    ErrorDetails errorResult = check responsePayload.cloneWithType();
    test:assertEquals(errorResult.message, "The calendar name must not be empty.");
}

@test:Config {}
function testAgendaRejectsEndNotAfterStart() returns error? {
    googleCalendarClient = newMockCalendarService();

    http:Response response = check testClient->get(string `/calendars/primary/agenda?startTime=${futureIsoTime(5)}&endTime=${futureIsoTime(1)}`);
    test:assertEquals(response.statusCode, 400);

    json responsePayload = check response.getJsonPayload();
    ErrorDetails errorResult = check responsePayload.cloneWithType();
    test:assertEquals(errorResult.message, "The agenda end time must be after the start time.");
}

@test:Config {}
function testRescheduleMeetingRejectsEndNotAfterStart() returns error? {
    MockCalendarService mockService = newMockCalendarService();
    mockService.knownEvents["primary/event-3"] = {
        kind: "calendar#event",
        etag: "etag",
        id: "event-3",
        status: "confirmed",
        summary: "Planning",
        'start: {dateTime: futureIsoTime(1)},
        end: {dateTime: futureIsoTime(1)},
        attendees: []
    };
    googleCalendarClient = mockService;

    RescheduleMeetingRequest request = {
        startTime: futureIsoTime(3),
        endTime: futureIsoTime(2),
        timeZone: "UTC"
    };
    http:Response response = check testClient->patch("/calendars/primary/meetings/event-3", request);
    test:assertEquals(response.statusCode, 400);

    json responsePayload = check response.getJsonPayload();
    ErrorDetails errorResult = check responsePayload.cloneWithType();
    test:assertEquals(errorResult.message, "The meeting end time must be after the start time.");
}

// ----------------------------------------------------------------------------------
// Unknown-calendar 404
// ----------------------------------------------------------------------------------
@test:Config {}
function testAgendaOnUnknownCalendarReturnsNotFound() returns error? {
    googleCalendarClient = newMockCalendarService();

    http:Response response = check testClient->get(string `/calendars/does-not-exist/agenda?startTime=${futureIsoTime(0)}&endTime=${futureIsoTime(5)}`);
    test:assertEquals(response.statusCode, 404);

    json responsePayload = check response.getJsonPayload();
    ErrorDetails errorResult = check responsePayload.cloneWithType();
    test:assertEquals(errorResult.message, "No calendar was found with id 'does-not-exist'.");
}

// ----------------------------------------------------------------------------------
// Upstream failure surfaces only the generic message, never the underlying detail.
// ----------------------------------------------------------------------------------
@test:Config {}
function testBookMeetingUpstreamFailureIsHidden() returns error? {
    MockCalendarService mockService = newMockCalendarService();
    mockService.failureToReturn = error("connection refused: secret-internal-detail clientSecret=abc123", statusCode = 503);
    googleCalendarClient = mockService;

    BookMeetingRequest request = {
        title: "Sprint planning",
        startTime: futureIsoTime(1),
        endTime: futureIsoTime(2),
        timeZone: "UTC",
        attendees: []
    };
    http:Response response = check testClient->post("/calendars/primary/meetings", request);
    test:assertEquals(response.statusCode, 502);

    json responsePayload = check response.getJsonPayload();
    ErrorDetails errorResult = check responsePayload.cloneWithType();
    test:assertEquals(errorResult.message, "The calendar service is currently unavailable. Please try again later.");
    test:assertTrue(!errorResult.message.includes("secret-internal-detail"));
    test:assertTrue(!errorResult.message.includes("clientSecret"));
}

@test:Config {}
function testCreateCalendarUpstreamFailureIsHidden() returns error? {
    MockCalendarService mockService = newMockCalendarService();
    mockService.failureToReturn = error("Google is throttling us: quotaExceeded, refreshToken=zzz");
    googleCalendarClient = mockService;

    CreateCalendarRequest request = {calendarName: "Team calendar"};
    http:Response response = check testClient->post("/calendars", request);
    test:assertEquals(response.statusCode, 502);

    json responsePayload = check response.getJsonPayload();
    ErrorDetails errorResult = check responsePayload.cloneWithType();
    test:assertEquals(errorResult.message, "The calendar service is currently unavailable. Please try again later.");
    test:assertTrue(!errorResult.message.includes("quotaExceeded"));
    test:assertTrue(!errorResult.message.includes("refreshToken"));
}

@test:Config {}
function testCancelMeetingUpstreamFailureIsHidden() returns error? {
    MockCalendarService mockService = newMockCalendarService();
    mockService.failureToReturn = error("network unreachable to Google, host=calendar.googleapis.com");
    googleCalendarClient = mockService;

    http:Response response = check testClient->delete("/calendars/primary/meetings/event-9");
    test:assertEquals(response.statusCode, 502);

    json responsePayload = check response.getJsonPayload();
    ErrorDetails errorResult = check responsePayload.cloneWithType();
    test:assertEquals(errorResult.message, "The calendar service is currently unavailable. Please try again later.");
    test:assertTrue(!errorResult.message.includes("googleapis.com"));
}
