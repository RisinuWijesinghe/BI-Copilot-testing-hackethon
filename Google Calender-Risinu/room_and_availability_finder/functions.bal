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

# Validates a quick-capture request, returning a message naming the broken rule if invalid.
#
# + request - the incoming quick-capture request
# + return - () if the request is valid, otherwise a message naming the rule that was broken
function validateQuickCaptureRequest(QuickCaptureRequest request) returns string? {
    if request.text.trim().length() == 0 {
        return "text must not be blank";
    }
    if request.calendar.trim().length() == 0 {
        return "calendar must not be blank";
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

# Queries free/busy information for the given calendars over the given period.
#
# + calendars - the calendar addresses to query
# + periodStart - the start of the period to query, in RFC3339 format
# + periodEnd - the end of the period to query, in RFC3339 format
# + return - the per-calendar availability results, or an error if the calendar service could not be reached at all
function queryCalendarAvailability(string[] calendars, string periodStart, string periodEnd) returns CalendarAvailability[]|error {
    gcalendar:FreeBusyRequestItem[] requestItems = from string calendarId in calendars
        select {id: calendarId};

    gcalendar:FreeBusyRequest freeBusyRequest = {
        timeMin: periodStart,
        timeMax: periodEnd,
        items: requestItems
    };

    gcalendar:FreeBusyResponse freeBusyResponse = check calendarClient->/freeBusy.post(freeBusyRequest);

    record {|gcalendar:FreeBusyCalendar...;|}? freeBusyCalendars = freeBusyResponse.calendars;
    CalendarAvailability[] calendarAvailabilities = [];
    if freeBusyCalendars is record {|gcalendar:FreeBusyCalendar...;|} {
        foreach string calendarId in calendars {
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
    return calendarAvailabilities;
}

# Queries free/busy information for the requested calendars and computes the common free slots.
#
# + request - the availability request
# + return - the availability response, or an error if the calendar service could not be reached at all
function getAvailability(AvailabilityRequest request) returns AvailabilityResponse|error {
    CalendarAvailability[] calendarAvailabilities = check queryCalendarAvailability(request.calendars, request.startTime, request.endTime);
    FreeSlot[] commonFreeSlots = check computeCommonFreeSlots(request.startTime, request.endTime, calendarAvailabilities);

    return {
        calendars: calendarAvailabilities,
        commonFreeSlots: commonFreeSlots
    };
}

# Validates a booking request, returning a message naming the broken rule if invalid.
#
# + request - the incoming booking request
# + return - () if the request is valid, otherwise a message naming the rule that was broken
function validateBookingRequest(BookingRequest request) returns string? {
    string? periodValidationError = validateAvailabilityRequest({
        calendars: request.calendars,
        startTime: request.startTime,
        endTime: request.endTime
    });
    if periodValidationError is string {
        return periodValidationError;
    }

    if request.durationMinutes <= 0 {
        return "durationMinutes must be greater than zero";
    }

    if request.title.trim().length() == 0 {
        return "title must not be blank";
    }

    if request.roomCalendar.trim().length() == 0 {
        return "roomCalendar must not be blank";
    }

    return ();
}

# Finds the earliest slot, among the given free slots, that is at least as long as the requested duration.
#
# + freeSlots - the free slots to search, assumed to be in chronological order
# + durationMinutes - the required length of the slot, in minutes
# + return - the earliest fitting window (clipped to the requested duration), or () if none fits
function findEarliestFittingSlot(FreeSlot[] freeSlots, int durationMinutes) returns FreeSlot|error? {
    time:Seconds requiredSeconds = <decimal>durationMinutes * 60;
    foreach FreeSlot freeSlot in freeSlots {
        time:Utc slotStartUtc = check time:utcFromString(freeSlot.startTime);
        time:Utc slotEndUtc = check time:utcFromString(freeSlot.endTime);
        time:Seconds slotSeconds = time:utcDiffSeconds(slotEndUtc, slotStartUtc);
        if slotSeconds >= requiredSeconds {
            time:Utc bookingEndUtc = time:utcAddSeconds(slotStartUtc, requiredSeconds);
            return {startTime: freeSlot.startTime, endTime: time:utcToString(bookingEndUtc)};
        }
    }
    return ();
}

# Finds the earliest window in the requested period where every participant is free for the requested duration,
# and books it on the nominated room calendar, inviting the rest of the participants.
#
# + request - the booking request
# + return - the booking response (whether or not a fitting window was found), or an error if the calendar
# service could not be reached at all
function bookEarliestSlot(BookingRequest request) returns BookingResponse|error {
    string[] allCalendars = request.calendars;
    if allCalendars.indexOf(request.roomCalendar) is () {
        allCalendars = [...allCalendars, request.roomCalendar];
    }

    CalendarAvailability[] calendarAvailabilities = check queryCalendarAvailability(allCalendars, request.startTime, request.endTime);

    string[] unreadableCalendars = from CalendarAvailability calendarAvailability in calendarAvailabilities
        where calendarAvailability?.'error is string
        select calendarAvailability.calendar;
    if unreadableCalendars.length() > 0 {
        return {
            booked: false,
            message: string `could not determine availability because these calendars could not be read: ${string:'join(", ", ...unreadableCalendars)}`
        };
    }

    FreeSlot[] commonFreeSlots = check computeCommonFreeSlots(request.startTime, request.endTime, calendarAvailabilities);

    FreeSlot? fittingSlot = check findEarliestFittingSlot(commonFreeSlots, request.durationMinutes);
    if fittingSlot is () {
        return {
            booked: false,
            message: string `no window of at least ${request.durationMinutes} minutes was free for every participant in the requested period`
        };
    }

    string[] invitees = from string calendarId in request.calendars
        where calendarId != request.roomCalendar
        select calendarId;

    gcalendar:EventAttendee[] attendees = from string invitee in invitees
        select {email: invitee};
    attendees.push({email: request.roomCalendar, 'resource: true});

    gcalendar:Event newEvent = {
        summary: request.title,
        'start: {dateTime: fittingSlot.startTime},
        end: {dateTime: fittingSlot.endTime},
        attendees: attendees
    };

    gcalendar:Event _ = check calendarClient->/calendars/[request.roomCalendar]/events.post(newEvent);

    return {
        booked: true,
        slot: fittingSlot,
        roomCalendar: request.roomCalendar,
        invitees: invitees,
        message: "booked the earliest available window"
    };
}

# Creates a calendar entry from a single line of free text on the nominated calendar.
#
# + request - the quick-capture request
# + return - the quick-capture response, or an error if the calendar service could not be reached at all
function quickCaptureEntry(QuickCaptureRequest request) returns QuickCaptureResponse|error {
    gcalendar:Event createdEvent = check calendarClient->/calendars/[request.calendar]/events/quickAdd.post(request.text);

    string title = createdEvent.summary ?: request.text;
    gcalendar:EventDateTime? eventStart = createdEvent?.'start;
    gcalendar:EventDateTime? eventEnd = createdEvent?.end;

    string? startTime = ();
    if eventStart is gcalendar:EventDateTime {
        startTime = eventStart.dateTime ?: eventStart.date;
    }
    string? endTime = ();
    if eventEnd is gcalendar:EventDateTime {
        endTime = eventEnd.dateTime ?: eventEnd.date;
    }

    return {
        calendar: request.calendar,
        title: title,
        startTime: startTime,
        endTime: endTime
    };
}
