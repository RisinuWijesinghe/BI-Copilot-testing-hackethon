import ballerina/log;
import ballerina/time;

// Generic, caller-safe error used for any failure originating from Google Calendar
// (rejected, throttled, unreachable, etc). The real cause is logged, never returned.
public type UpstreamFailureError distinct error;

const string UPSTREAM_FAILURE_MESSAGE = "The calendar service is currently unavailable. Please try again later.";

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
