import ballerina/time;
import ballerinax/googleapis.gcalendar;

# Maximum length of the requested period, in days.
const int MAX_PERIOD_DAYS = 31;

# Validates the availability request, returning a message naming the broken rule if invalid.
#
# + request - the incoming availability request
# + return - () if the request is valid, otherwise a message naming the rule that was broken
function validateAvailabilityRequest(AvailabilityRequest request) returns string? {
    if request.calendars.length() == 0 {
        return "at least one calendar must be provided";
    }

    time:Utc|time:Error startTimeUtc = time:utcFromString(request.startTime);
    if startTimeUtc is time:Error {
        return "startTime must be a valid RFC3339 timestamp";
    }

    time:Utc|time:Error endTimeUtc = time:utcFromString(request.endTime);
    if endTimeUtc is time:Error {
        return "endTime must be a valid RFC3339 timestamp";
    }

    if endTimeUtc <= startTimeUtc {
        return "endTime must be after startTime";
    }

    decimal periodSeconds = time:utcDiffSeconds(endTimeUtc, startTimeUtc);
    decimal maxPeriodSeconds = <decimal>MAX_PERIOD_DAYS * 24 * 60 * 60;
    if periodSeconds > maxPeriodSeconds {
        return string `the requested period must not exceed ${MAX_PERIOD_DAYS} days`;
    }

    return ();
}

# Computes the gaps within the requested period during which every calendar that could be read is simultaneously free.
#
# + periodStart - the start of the requested period, in RFC3339 format
# + periodEnd - the end of the requested period, in RFC3339 format
# + calendars - the per-calendar availability results (errored calendars are ignored, since their busy times are unknown)
# + return - the free slots common to all readable calendars, or an error if a timestamp could not be parsed
function computeCommonFreeSlots(string periodStart, string periodEnd, CalendarAvailability[] calendars) returns FreeSlot[]|error {
    time:Utc periodStartUtc = check time:utcFromString(periodStart);
    time:Utc periodEndUtc = check time:utcFromString(periodEnd);

    [time:Utc, time:Utc][] busyIntervals = [];
    foreach CalendarAvailability calendarAvailability in calendars {
        BusyBlock[]? busyBlocks = calendarAvailability.busy;
        if busyBlocks is BusyBlock[] {
            foreach BusyBlock busyBlock in busyBlocks {
                time:Utc busyStartUtc = check time:utcFromString(busyBlock.startTime);
                time:Utc busyEndUtc = check time:utcFromString(busyBlock.endTime);

                time:Utc clampedStart = busyStartUtc < periodStartUtc ? periodStartUtc : busyStartUtc;
                time:Utc clampedEnd = busyEndUtc > periodEndUtc ? periodEndUtc : busyEndUtc;
                if clampedStart < clampedEnd {
                    busyIntervals.push([clampedStart, clampedEnd]);
                }
            }
        }
    }

    [time:Utc, time:Utc][] sortedIntervals = from [time:Utc, time:Utc] interval in busyIntervals
        order by interval[0] ascending
        select interval;

    [time:Utc, time:Utc][] mergedIntervals = [];
    foreach [time:Utc, time:Utc] interval in sortedIntervals {
        if mergedIntervals.length() == 0 {
            mergedIntervals.push(interval);
            continue;
        }
        int lastIndex = mergedIntervals.length() - 1;
        time:Utc lastEnd = mergedIntervals[lastIndex][1];
        if interval[0] <= lastEnd {
            time:Utc newEnd = interval[1] > lastEnd ? interval[1] : lastEnd;
            mergedIntervals[lastIndex] = [mergedIntervals[lastIndex][0], newEnd];
        } else {
            mergedIntervals.push(interval);
        }
    }

    FreeSlot[] freeSlots = [];
    time:Utc cursor = periodStartUtc;
    foreach [time:Utc, time:Utc] interval in mergedIntervals {
        time:Utc busyStart = interval[0];
        time:Utc busyEnd = interval[1];
        if cursor < busyStart {
            freeSlots.push({startTime: time:utcToString(cursor), endTime: time:utcToString(busyStart)});
        }
        if busyEnd > cursor {
            cursor = busyEnd;
        }
    }
    if cursor < periodEndUtc {
        freeSlots.push({startTime: time:utcToString(cursor), endTime: time:utcToString(periodEndUtc)});
    }

    return freeSlots;
}

# Queries free/busy information for the requested calendars and computes the common free slots.
#
# + request - the availability request
# + return - the availability response, or an error if the calendar service could not be reached at all
function getAvailability(AvailabilityRequest request) returns AvailabilityResponse|error {
    gcalendar:FreeBusyRequestItem[] requestItems = from string calendarId in request.calendars
        select {id: calendarId};

    gcalendar:FreeBusyRequest freeBusyRequest = {
        timeMin: request.startTime,
        timeMax: request.endTime,
        items: requestItems
    };

    gcalendar:FreeBusyResponse freeBusyResponse = check calendarClient->/freeBusy.post(freeBusyRequest);

    record {|gcalendar:FreeBusyCalendar...;|}? freeBusyCalendars = freeBusyResponse.calendars;
    CalendarAvailability[] calendarAvailabilities = [];
    if freeBusyCalendars is record {|gcalendar:FreeBusyCalendar...;|} {
        foreach string calendarId in request.calendars {
            if freeBusyCalendars.hasKey(calendarId) {
                gcalendar:FreeBusyCalendar freeBusyCalendar = freeBusyCalendars.get(calendarId);
                calendarAvailabilities.push(toCalendarAvailability(calendarId, freeBusyCalendar));
            } else {
                calendarAvailabilities.push({
                    calendar: calendarId,
                    'error: "calendar availability could not be retrieved"
                });
            }
        }
    }

    FreeSlot[] commonFreeSlots = check computeCommonFreeSlots(request.startTime, request.endTime, calendarAvailabilities);

    return {
        calendars: calendarAvailabilities,
        commonFreeSlots: commonFreeSlots
    };
}
