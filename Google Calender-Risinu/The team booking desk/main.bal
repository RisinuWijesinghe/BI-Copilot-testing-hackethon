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

        CalendarService|error calendarClient = getCalendarClient();
        if calendarClient is error {
            UpstreamFailureError upstreamError = toUpstreamFailure(calendarClient, "getCalendarClient");
            return <http:BadGateway>{
                body: {message: upstreamError.message()}
            };
        }

        calendar:CalendarResource|error result = calendarClient.createCalendar(calendarName);
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

        CalendarService|error calendarClient = getCalendarClient();
        if calendarClient is error {
            UpstreamFailureError upstreamError = toUpstreamFailure(calendarClient, "getCalendarClient");
            return <http:BadGateway>{
                body: {message: upstreamError.message()}
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

        calendar:Event|error result = calendarClient.createEvent(calendarId, inputEvent);
        if result is error {
            UpstreamFailureError upstreamError = toUpstreamFailure(result, "createEvent");
            return <http:BadGateway>{
                body: {message: upstreamError.message()}
            };
        }

        string? eventLink = result.htmlLink;
        return {eventId: result.id, eventLink: eventLink ?: ""};
    }

    // Returns the agenda for a calendar over a date range as individual occurrences,
    // sorted earliest first and capped at a sensible number of entries per request.
    // When a search phrase is supplied, only entries matching the title, description,
    // location, or an attendee are returned.
    resource function get calendars/[string calendarId]/agenda(string startTime, string endTime, string? search = (), int maxResults = MAX_AGENDA_RESULTS)
            returns AgendaItem[]|http:BadRequest|http:NotFound|http:BadGateway {
        time:Utc|error rangeStartUtc = time:utcFromString(startTime);
        if rangeStartUtc is error {
            return <http:BadRequest>{
                body: {message: "The agenda start time is invalid."}
            };
        }
        time:Utc|error rangeEndUtc = time:utcFromString(endTime);
        if rangeEndUtc is error {
            return <http:BadRequest>{
                body: {message: "The agenda end time is invalid."}
            };
        }
        if time:utcDiffSeconds(rangeEndUtc, rangeStartUtc) <= 0d {
            return <http:BadRequest>{
                body: {message: "The agenda end time must be after the start time."}
            };
        }
        int cappedMaxResults = maxResults > MAX_AGENDA_RESULTS ? MAX_AGENDA_RESULTS : maxResults;
        if cappedMaxResults < 1 {
            return <http:BadRequest>{
                body: {message: "The maximum number of results must be at least one."}
            };
        }

        CalendarService|error calendarClient = getCalendarClient();
        if calendarClient is error {
            UpstreamFailureError upstreamError = toUpstreamFailure(calendarClient, "getCalendarClient");
            return <http:BadGateway>{
                body: {message: upstreamError.message()}
            };
        }

        calendar:EventFilterCriteria filter = {
            timeMin: startTime,
            timeMax: endTime,
            singleEvents: true,
            orderBy: calendar:START_TIME
        };
        stream<calendar:Event, error?>|error eventStream = calendarClient.getEvents(calendarId, filter);
        if eventStream is error {
            if isNotFoundFailure(eventStream) {
                return <http:NotFound>{
                    body: {message: string `No calendar was found with id '${calendarId}'.`}
                };
            }
            UpstreamFailureError upstreamError = toUpstreamFailure(eventStream, "getEvents");
            return <http:BadGateway>{
                body: {message: upstreamError.message()}
            };
        }

        calendar:Event[] matchingEvents = [];
        string? searchPhrase = search;
        error? streamError = eventStream.forEach(function(calendar:Event event) {
            if matchesOptionalSearchPhrase(event, searchPhrase) {
                matchingEvents.push(event);
            }
        });
        if streamError is error {
            if isNotFoundFailure(streamError) {
                return <http:NotFound>{
                    body: {message: string `No calendar was found with id '${calendarId}'.`}
                };
            }
            UpstreamFailureError upstreamError = toUpstreamFailure(streamError, "getEvents");
            return <http:BadGateway>{
                body: {message: upstreamError.message()}
            };
        }

        AgendaItem[] agenda = from calendar:Event event in matchingEvents
            select toAgendaItem(event);
        int resultCount = agenda.length() > cappedMaxResults ? cappedMaxResults : agenda.length();
        return agenda.slice(0, resultCount);
    }

    // Reschedules an existing meeting to a new start and end time, leaving every other
    // detail unchanged, and notifies the invitees of the change.
    resource function patch calendars/[string calendarId]/meetings/[string eventId](@http:Payload RescheduleMeetingRequest request)
            returns BookMeetingResponse|http:BadRequest|http:NotFound|http:BadGateway {
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

        CalendarService|error calendarClient = getCalendarClient();
        if calendarClient is error {
            UpstreamFailureError upstreamError = toUpstreamFailure(calendarClient, "getCalendarClient");
            return <http:BadGateway>{
                body: {message: upstreamError.message()}
            };
        }

        calendar:Event|error existingEvent = calendarClient.getEvent(calendarId, eventId);
        if existingEvent is error {
            if isNotFoundFailure(existingEvent) {
                return <http:NotFound>{
                    body: {message: string `No meeting with id '${eventId}' was found on calendar '${calendarId}'.`}
                };
            }
            UpstreamFailureError upstreamError = toUpstreamFailure(existingEvent, "getEvent");
            return <http:BadGateway>{
                body: {message: upstreamError.message()}
            };
        }

        calendar:InputEvent updatedEvent = {
            summary: existingEvent.summary,
            description: existingEvent.description,
            location: existingEvent.location,
            'start: {dateTime: request.startTime, timeZone: request.timeZone},
            end: {dateTime: request.endTime, timeZone: request.timeZone},
            attendees: existingEvent.attendees
        };

        calendar:Event|error result = calendarClient.updateEvent(calendarId, eventId, updatedEvent, {sendUpdates: "all"});
        if result is error {
            if isNotFoundFailure(result) {
                return <http:NotFound>{
                    body: {message: string `No meeting with id '${eventId}' was found on calendar '${calendarId}'.`}
                };
            }
            UpstreamFailureError upstreamError = toUpstreamFailure(result, "updateEvent");
            return <http:BadGateway>{
                body: {message: upstreamError.message()}
            };
        }

        string? eventLink = result.htmlLink;
        return {eventId: result.id, eventLink: eventLink ?: ""};
    }

    // Cancels a booked meeting and notifies the attendees. Calling this twice for the
    // same meeting is not an error - once the meeting is gone, the caller's desired
    // outcome already holds, so a repeat call is just as successful as the first.
    resource function delete calendars/[string calendarId]/meetings/[string eventId]()
            returns CancelMeetingResponse|http:BadGateway {
        CalendarService|error calendarClient = getCalendarClient();
        if calendarClient is error {
            UpstreamFailureError upstreamError = toUpstreamFailure(calendarClient, "getCalendarClient");
            return <http:BadGateway>{
                body: {message: upstreamError.message()}
            };
        }

        error? result = calendarClient.deleteEvent(calendarId, eventId);
        if result is error {
            if isNotFoundFailure(result) {
                return {message: "The meeting has been cancelled."};
            }
            UpstreamFailureError upstreamError = toUpstreamFailure(result, "deleteEvent");
            return <http:BadGateway>{
                body: {message: upstreamError.message()}
            };
        }

        return {message: "The meeting has been cancelled."};
    }
}
