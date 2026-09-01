import ballerina/http;
import ballerina/time;
import ballerinax/googleapis.calendar;

configurable int servicePort = 8080;

service /calendar on new http:Listener(servicePort) {

    // Creates a brand new shared calendar from a caller-supplied name and
    // returns the identifier needed to refer to it later.
    resource function post calendars(@http:Payload CreateCalendarRequest request)
            returns CreateCalendarResponse|http:BadRequest|http:BadGateway {
        string calendarName = request.calendarName.trim();
        if calendarName.length() == 0 {
            return <http:BadRequest>{
                body: {message: "The calendar name must not be empty."}
            };
        }

        calendar:CalendarResource|error result = googleCalendarClient->createCalendar(calendarName);
        if result is error {
            UpstreamFailureError upstreamError = toUpstreamFailure(result, "createCalendar");
            return <http:BadGateway>{
                body: {message: upstreamError.message()}
            };
        }

        return {calendarId: result.id};
    }

    // Books a meeting on a caller-named calendar and returns the identifier of the
    // created event along with a link that can be opened.
    resource function post calendars/[string calendarId]/meetings(@http:Payload BookMeetingRequest request)
            returns BookMeetingResponse|http:BadRequest|http:BadGateway {
        time:Utc|error startUtc = toUtc(request.startTime, request.timeZone);
        if startUtc is error {
            return <http:BadRequest>{
                body: {message: "The start time or timezone provided is invalid."}
            };
        }
        time:Utc|error endUtc = toUtc(request.endTime, request.timeZone);
        if endUtc is error {
            return <http:BadRequest>{
                body: {message: "The end time or timezone provided is invalid."}
            };
        }

        string? validationError = validateMeetingTimes(startUtc, endUtc);
        if validationError is string {
            return <http:BadRequest>{
                body: {message: validationError}
            };
        }

        calendar:Attendee[] attendees = from string email in request.attendees
            select {email: email};

        calendar:InputEvent inputEvent = {
            summary: request.title,
            description: request.description,
            'start: {dateTime: request.startTime, timeZone: request.timeZone},
            end: {dateTime: request.endTime, timeZone: request.timeZone},
            attendees: attendees
        };

        calendar:Event|error result = googleCalendarClient->createEvent(calendarId, inputEvent);
        if result is error {
            UpstreamFailureError upstreamError = toUpstreamFailure(result, "createEvent");
            return <http:BadGateway>{
                body: {message: upstreamError.message()}
            };
        }

        string? eventLink = result.htmlLink;
        return {eventId: result.id, eventLink: eventLink ?: ""};
    }
}
