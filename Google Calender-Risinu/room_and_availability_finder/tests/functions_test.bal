import ballerina/test;
import ballerinax/googleapis.gcalendar;

@test:Config {}
function testFindsCommonFreeWindowAndBooksIt() returns error? {
    gcalendar:Client mockClient = test:mock(gcalendar:Client);
    calendarClient = mockClient;

    gcalendar:FreeBusyResponse freeBusyResponse = {
        calendars: {
            "colleague@example.com": {
                busy: [
                    {'start: "2026-09-07T08:00:00Z", end: "2026-09-07T10:00:00Z"}
                ]
            },
            "room-a@resource.example.com": {
                busy: []
            }
        }
    };
    test:prepare(mockClient).whenResource("freeBusy").onMethod("post").thenReturn(freeBusyResponse);

    gcalendar:Event createdEvent = {
        id: "created-event-id",
        summary: "Weekly Standup",
        'start: {dateTime: "2026-09-07T10:00:00Z"},
        end: {dateTime: "2026-09-07T10:30:00Z"}
    };
    test:prepare(mockClient).whenResource("calendars/:calendarId/events").onMethod("post").thenReturn(createdEvent);

    BookingRequest request = {
        calendars: ["colleague@example.com"],
        startTime: "2026-09-07T08:00:00Z",
        endTime: "2026-09-07T12:00:00Z",
        durationMinutes: 30,
        title: "Weekly Standup",
        roomCalendar: "room-a@resource.example.com"
    };

    BookingResponse response = check bookEarliestSlot(request);

    test:assertTrue(response.booked, msg = "expected a fitting window to be found and booked");
    FreeSlot? slot = response.slot;
    if slot is FreeSlot {
        test:assertEquals(slot.startTime, "2026-09-07T10:00:00Z", msg = "booking should start right after the busy block ends");
        test:assertEquals(slot.endTime, "2026-09-07T10:30:00Z", msg = "booking should last the requested duration");
    } else {
        test:assertTrue(false, msg = "expected a slot to be present in a successful booking");
    }
    test:assertEquals(response.roomCalendar, "room-a@resource.example.com", msg = "booking should be made on the nominated room calendar");
    test:assertEquals(response.invitees, ["colleague@example.com"], msg = "the non-room calendars should be invited");
}

@test:Config {}
function testNoAvailabilityIsACleanSuccess() returns error? {
    gcalendar:Client mockClient = test:mock(gcalendar:Client);
    calendarClient = mockClient;

    gcalendar:FreeBusyResponse freeBusyResponse = {
        calendars: {
            "colleague@example.com": {
                busy: [
                    {'start: "2026-09-07T08:00:00Z", end: "2026-09-07T12:00:00Z"}
                ]
            },
            "room-a@resource.example.com": {
                busy: []
            }
        }
    };
    test:prepare(mockClient).whenResource("freeBusy").onMethod("post").thenReturn(freeBusyResponse);

    BookingRequest request = {
        calendars: ["colleague@example.com"],
        startTime: "2026-09-07T08:00:00Z",
        endTime: "2026-09-07T12:00:00Z",
        durationMinutes: 30,
        title: "Weekly Standup",
        roomCalendar: "room-a@resource.example.com"
    };

    BookingResponse response = check bookEarliestSlot(request);

    test:assertTrue(!response.booked, msg = "no fitting window should result in booked being false, not an error");
    test:assertTrue(response.message.length() > 0, msg = "a clear explanation should be given when nothing was booked");
}

@test:Config {}
function testPerCalendarFailureIsReportedAgainstThatCalendar() returns error? {
    gcalendar:Client mockClient = test:mock(gcalendar:Client);
    calendarClient = mockClient;

    gcalendar:FreeBusyResponse freeBusyResponse = {
        calendars: {
            "missing-room@resource.example.com": {
                errors: [
                    {domain: "global", reason: "notFound"}
                ]
            },
            "colleague@example.com": {
                busy: []
            }
        }
    };
    test:prepare(mockClient).whenResource("freeBusy").onMethod("post").thenReturn(freeBusyResponse);

    AvailabilityRequest request = {
        calendars: ["missing-room@resource.example.com", "colleague@example.com"],
        startTime: "2026-09-07T08:00:00Z",
        endTime: "2026-09-07T12:00:00Z"
    };

    AvailabilityResponse response = check getAvailability(request);

    CalendarAvailability[] calendarAvailabilities = response.calendars;
    test:assertEquals(calendarAvailabilities.length(), 2, msg = "both requested calendars should be represented in the response");

    CalendarAvailability missingRoomAvailability = calendarAvailabilities[0];
    test:assertEquals(missingRoomAvailability.calendar, "missing-room@resource.example.com", msg = "the first entry should correspond to the missing room");
    string? errorMessage = missingRoomAvailability?.'error;
    if errorMessage is string {
        test:assertEquals(errorMessage, "calendar was not found", msg = "the error should be reported in our own wording, not Google's");
    } else {
        test:assertTrue(false, msg = "expected an error to be reported for the missing room");
    }

    CalendarAvailability colleagueAvailability = calendarAvailabilities[1];
    test:assertEquals(colleagueAvailability.calendar, "colleague@example.com", msg = "the second entry should correspond to the colleague calendar");
    test:assertTrue(colleagueAvailability?.'error is (), msg = "the colleague calendar should not report an error");
}

@test:Config {}
function testTotalFailureToReachCalendarServiceSurfacesAsError() returns error? {
    gcalendar:Client mockClient = test:mock(gcalendar:Client);
    calendarClient = mockClient;

    gcalendar:Error connectionError = error("connection refused");
    test:prepare(mockClient).whenResource("freeBusy").onMethod("post").thenReturn(connectionError);

    AvailabilityRequest request = {
        calendars: ["colleague@example.com"],
        startTime: "2026-09-07T08:00:00Z",
        endTime: "2026-09-07T12:00:00Z"
    };

    AvailabilityResponse|error response = getAvailability(request);
    test:assertTrue(response is error, msg = "a total failure to reach the calendar service should surface as an error");
}

@test:Config {}
function testOccurrencesAreExpandedRatherThanTheRecurrenceRule() returns error? {
    gcalendar:Client mockClient = test:mock(gcalendar:Client);
    calendarClient = mockClient;

    gcalendar:Events instancesResponse = {
        items: [
            {'start: {dateTime: "2026-09-07T09:00:00Z"}, end: {dateTime: "2026-09-07T09:15:00Z"}, status: "confirmed"},
            {'start: {dateTime: "2026-09-14T10:00:00Z"}, end: {dateTime: "2026-09-14T10:15:00Z"}, status: "confirmed"},
            {'start: {dateTime: "2026-09-21T09:00:00Z"}, end: {dateTime: "2026-09-21T09:15:00Z"}, status: "cancelled"}
        ]
    };
    test:prepare(mockClient).whenResource("calendars/:calendarId/events/:eventId/instances").onMethod("get").thenReturn(instancesResponse);

    OccurrencesResponse response = check listBookingOccurrences(
        "room-a@resource.example.com",
        "recurring-event-id",
        "2026-09-01T00:00:00Z",
        "2026-09-30T00:00:00Z"
    );

    test:assertEquals(response.occurrences.length(), 3, msg = "all three expanded occurrences should be returned");
    test:assertEquals(response.occurrences[0].startTime, "2026-09-07T09:00:00Z", msg = "the first occurrence should keep its original time");
    test:assertEquals(response.occurrences[1].startTime, "2026-09-14T10:00:00Z", msg = "the moved occurrence should show its new time, not the original pattern");
    test:assertEquals(response.occurrences[2].status, "cancelled", msg = "a dropped occurrence should be reported as cancelled");
}

@test:Config {}
function testEmptyCalendarSetIsRejected() {
    AvailabilityRequest request = {
        calendars: [],
        startTime: "2026-09-07T08:00:00Z",
        endTime: "2026-09-07T12:00:00Z"
    };

    string? validationError = validateAvailabilityRequest(request);
    test:assertEquals(validationError, "at least one calendar must be provided", msg = "an empty calendar set should name that rule");
}

@test:Config {}
function testPeriodEndingBeforeItStartsIsRejected() {
    AvailabilityRequest request = {
        calendars: ["colleague@example.com"],
        startTime: "2026-09-07T12:00:00Z",
        endTime: "2026-09-07T08:00:00Z"
    };

    string? validationError = validateAvailabilityRequest(request);
    test:assertEquals(validationError, "endTime must be after startTime", msg = "an inverted period should name that rule");
}

@test:Config {}
function testPeriodLongerThanAMonthIsRejected() {
    AvailabilityRequest request = {
        calendars: ["colleague@example.com"],
        startTime: "2026-09-01T00:00:00Z",
        endTime: "2026-11-01T00:00:00Z"
    };

    string? validationError = validateAvailabilityRequest(request);
    test:assertEquals(validationError, "the requested period must not exceed 31 days", msg = "a period longer than about a month should name that rule");
}

@test:Config {}
function testBlankQuickCaptureTextIsRejected() {
    QuickCaptureRequest request = {
        calendar: "colleague@example.com",
        text: "   "
    };

    string? validationError = validateQuickCaptureRequest(request);
    test:assertEquals(validationError, "text must not be blank", msg = "blank quick-capture text should name that rule");
}

@test:Config {}
function testRecurringBookingRequiresExactlyOneEndCondition() {
    RecurringBookingRequest request = {
        calendars: ["colleague@example.com"],
        startTime: "2026-09-07T08:00:00Z",
        endTime: "2026-09-07T12:00:00Z",
        durationMinutes: 15,
        title: "Standup",
        roomCalendar: "room-a@resource.example.com",
        weekdays: ["MO", "WE", "FR"],
        untilDate: "2026-12-01T00:00:00Z",
        occurrenceCount: 10
    };

    string? validationError = validateRecurringBookingRequest(request);
    test:assertEquals(validationError, "only one of untilDate or occurrenceCount must be provided, not both", msg = "providing both end conditions should be rejected");
}

@test:Config {}
function testRecurringBookingRequiresAtLeastOneWeekday() {
    RecurringBookingRequest request = {
        calendars: ["colleague@example.com"],
        startTime: "2026-09-07T08:00:00Z",
        endTime: "2026-09-07T12:00:00Z",
        durationMinutes: 15,
        title: "Standup",
        roomCalendar: "room-a@resource.example.com",
        weekdays: [],
        occurrenceCount: 10
    };

    string? validationError = validateRecurringBookingRequest(request);
    test:assertEquals(validationError, "at least one weekday must be provided", msg = "an empty weekday set should name that rule");
}

@test:Config {}
function testMoveToSameDestinationIsRejected() {
    MoveBookingRequest request = {
        sourceCalendar: "room-a@resource.example.com",
        eventId: "event-1",
        destinationCalendar: "room-a@resource.example.com"
    };

    string? validationError = validateMoveBookingRequest(request);
    test:assertEquals(validationError, "destinationCalendar must be different from sourceCalendar", msg = "moving to the same calendar should be refused as a pointless round trip");
}

@test:Config {}
function testMoveToDifferentDestinationIsValid() {
    MoveBookingRequest request = {
        sourceCalendar: "room-a@resource.example.com",
        eventId: "event-1",
        destinationCalendar: "room-b@resource.example.com"
    };

    string? validationError = validateMoveBookingRequest(request);
    test:assertEquals(validationError, (), msg = "moving to a different calendar should be accepted");
}
