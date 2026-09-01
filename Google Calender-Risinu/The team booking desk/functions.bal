import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerinax/googleapis.calendar;

// Generic, caller-safe error used for any failure originating from Google Calendar
// (rejected, throttled, unreachable, etc). The real cause is logged, never returned.
public type UpstreamFailureError distinct error;

const string UPSTREAM_FAILURE_MESSAGE = "The calendar service is currently unavailable. Please try again later.";

// Maximum agenda entries returned for a single request, so nobody can ask for a
// decade of events in one go.
public const int MAX_AGENDA_RESULTS = 200;

// Validates that the end time is after the start time and that the meeting does not
// start in the past. Returns a plain-English message describing the first violation found.
function validateMeetingTimes(time:Utc startUtc, time:Utc endUtc) returns string? {
    if time:utcDiffSeconds(endUtc, startUtc) <= 0d {
        return "The meeting end time must be after the start time.";
    }
    time:Utc currentUtc = time:utcNow();
    if time:utcDiffSeconds(startUtc, currentUtc) < 0d {
        return "The meeting start time must not be in the past.";
    }
    return ();
}

// Parses a date-time string paired with an IANA timezone into a `time:Utc` instant for validation.
function toUtc(string dateTime, string timeZone) returns time:Utc|error {
    time:Civil civil = check time:civilFromString(dateTime);
    civil.utcOffset = ();
    civil.timeAbbrev = timeZone;
    string civilString = check time:civilToString(civil);
    return time:utcFromString(civilString);
}

// Wraps a Google Calendar operation, logging the real error server-side and surfacing
// only a generic upstream failure to the caller - never Google's raw response,
// credentials, or a stack trace.
function toUpstreamFailure(error cause, string operation) returns UpstreamFailureError {
    log:printError(string `Google Calendar operation failed: ${operation}`, 'error = cause);
    return error UpstreamFailureError(UPSTREAM_FAILURE_MESSAGE);
}

// Determines whether a Google Calendar failure was caused by a missing/inaccessible
// calendar or event (HTTP 404), by walking the error's cause chain.
function isNotFoundFailure(error cause) returns boolean {
    error? current = cause;
    while current is error {
        if current is http:ClientRequestError {
            int statusCode = current.detail().statusCode;
            if statusCode == 404 {
                return true;
            }
        }
        current = current.cause();
    }
    return false;
}

// Extracts the display value (date-time, falling back to date) from a Google Calendar `Time`.
function toTimeValue(calendar:Time eventTime) returns string {
    string? dateTime = eventTime.dateTime;
    if dateTime is string {
        return dateTime;
    }
    string? date = eventTime.date;
    return date ?: "";
}

// Extracts attendee email addresses from a Google Calendar event's attendee list.
function toAttendeeEmails(calendar:Attendee[]? attendees) returns string[] {
    if attendees is () {
        return [];
    }
    return from calendar:Attendee attendee in attendees
        select attendee.email;
}

// Maps a Google Calendar `Event` occurrence to the UI-facing `AgendaItem` shape.
function toAgendaItem(calendar:Event event) returns AgendaItem => {
    title: event.summary ?: "",
    startTime: toTimeValue(event.'start ?: {}),
    endTime: toTimeValue(event.end ?: {}),
    location: event.location ?: "",
    attendees: toAttendeeEmails(event.attendees)
};
