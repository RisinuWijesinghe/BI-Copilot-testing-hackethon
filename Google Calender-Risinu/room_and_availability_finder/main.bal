import ballerina/http;
import ballerina/log;

service /availability on new http:Listener(8080) {

    # Finds the busy blocks for each requested calendar and the gaps where all of them are simultaneously free.
    #
    # + request - the set of calendars and the period to check
    # + return - the per-calendar availability and common free slots, a bad request if the request is invalid,
    # or a bad gateway if the calendar service could not be reached at all
    resource function post .(@http:Payload AvailabilityRequest request) returns AvailabilityResponse|http:BadRequest|http:BadGateway {
        string? validationError = validateAvailabilityRequest(request);
        if validationError is string {
            return <http:BadRequest>{
                body: {message: validationError}
            };
        }

        AvailabilityResponse|error availabilityResponse = getAvailability(request);
        if availabilityResponse is error {
            log:printError("failed to reach the calendar service", availabilityResponse);
            return <http:BadGateway>{
                body: {message: "the calendar service could not be reached"}
            };
        }

        return availabilityResponse;
    }

    # Finds the earliest window where every participant is free for the requested duration and books it on the
    # nominated room calendar, inviting the rest of the participants. A period with no fitting window is a normal,
    # successful answer.
    #
    # + request - the participants, period, duration, title, and room to book on
    # + return - what got booked (or an explanation that nothing fit), a bad request if the request is invalid,
    # or a bad gateway if the calendar service could not be reached at all
    resource function post book(@http:Payload BookingRequest request) returns BookingResponse|http:BadRequest|http:BadGateway {
        string? validationError = validateBookingRequest(request);
        if validationError is string {
            return <http:BadRequest>{
                body: {message: validationError}
            };
        }

        BookingResponse|error bookingResponse = bookEarliestSlot(request);
        if bookingResponse is error {
            log:printError("failed to reach the calendar service", bookingResponse);
            return <http:BadGateway>{
                body: {message: "the calendar service could not be reached"}
            };
        }

        return bookingResponse;
    }

    # Creates a calendar entry from a single line of everyday text, without the caller filling in structured fields.
    #
    # + request - the calendar to create the entry on and the free text describing it
    # + return - what got created, a bad request if the text is blank, or a bad gateway if the calendar service
    # could not be reached at all
    resource function post quickCapture(@http:Payload QuickCaptureRequest request) returns QuickCaptureResponse|http:BadRequest|http:BadGateway {
        string? validationError = validateQuickCaptureRequest(request);
        if validationError is string {
            return <http:BadRequest>{
                body: {message: validationError}
            };
        }

        QuickCaptureResponse|error quickCaptureResponse = quickCaptureEntry(request);
        if quickCaptureResponse is error {
            log:printError("failed to reach the calendar service", quickCaptureResponse);
            return <http:BadGateway>{
                body: {message: "the calendar service could not be reached"}
            };
        }

        return quickCaptureResponse;
    }

    # Finds the earliest window where every participant is free for the requested duration and books it as a
    # weekly-recurring meeting on the nominated room calendar, inviting the rest of the participants. A period
    # with no fitting starting window is a normal, successful answer.
    #
    # + request - the participants, period, duration, title, room, and weekly recurrence pattern
    # + return - what got booked (or an explanation that nothing fit), a bad request if the request is invalid,
    # or a bad gateway if the calendar service could not be reached at all
    resource function post bookRecurring(@http:Payload RecurringBookingRequest request) returns RecurringBookingResponse|http:BadRequest|http:BadGateway {
        string? validationError = validateRecurringBookingRequest(request);
        if validationError is string {
            return <http:BadRequest>{
                body: {message: validationError}
            };
        }

        RecurringBookingResponse|error recurringBookingResponse = bookRecurringSlot(request);
        if recurringBookingResponse is error {
            log:printError("failed to reach the calendar service", recurringBookingResponse);
            return <http:BadGateway>{
                body: {message: "the calendar service could not be reached"}
            };
        }

        return recurringBookingResponse;
    }

    # Lists the expanded occurrences of a recurring booking within a date range, so a dashboard can spot
    # occurrences that were moved or dropped.
    #
    # + roomCalendar - the calendar address the recurring booking lives on
    # + eventId - the identifier of the recurring booking
    # + rangeStart - the start of the date range to list occurrences within, in RFC3339 format
    # + rangeEnd - the end of the date range to list occurrences within, in RFC3339 format
    # + return - the expanded occurrences, a bad request if the request is invalid, or a bad gateway if the
    # calendar service could not be reached at all
    resource function get occurrences(string roomCalendar, string eventId, string rangeStart, string rangeEnd)
            returns OccurrencesResponse|http:BadRequest|http:BadGateway {
        string? validationError = validateOccurrencesRequest(roomCalendar, eventId, rangeStart, rangeEnd);
        if validationError is string {
            return <http:BadRequest>{
                body: {message: validationError}
            };
        }

        OccurrencesResponse|error occurrencesResponse = listBookingOccurrences(roomCalendar, eventId, rangeStart, rangeEnd);
        if occurrencesResponse is error {
            log:printError("failed to reach the calendar service", occurrencesResponse);
            return <http:BadGateway>{
                body: {message: "the calendar service could not be reached"}
            };
        }

        return occurrencesResponse;
    }

    # Relocates an existing booking from one room calendar to another.
    #
    # + request - the source calendar, event identifier, and destination calendar
    # + return - what moved where, a bad request if the request is invalid (including a no-op same-destination
    # move), or a bad gateway if the calendar service could not be reached at all
    resource function post move(@http:Payload MoveBookingRequest request) returns MoveBookingResponse|http:BadRequest|http:BadGateway {
        string? validationError = validateMoveBookingRequest(request);
        if validationError is string {
            return <http:BadRequest>{
                body: {message: validationError}
            };
        }

        MoveBookingResponse|error moveBookingResponse = moveBooking(request);
        if moveBookingResponse is error {
            log:printError("failed to reach the calendar service", moveBookingResponse);
            return <http:BadGateway>{
                body: {message: "the calendar service could not be reached"}
            };
        }

        return moveBookingResponse;
    }
}
