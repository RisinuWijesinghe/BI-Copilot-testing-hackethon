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
}
