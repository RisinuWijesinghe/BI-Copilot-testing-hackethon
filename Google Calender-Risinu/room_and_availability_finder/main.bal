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
}
