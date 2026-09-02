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

    gcalendar:Client activeCalendarClient = check getCalendarClient();
    gcalendar:FreeBusyResponse freeBusyResponse = check activeCalendarClient->/freeBusy.post(freeBusyRequest);

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

# Finds the calendars, among the given availability results, that could not be read.
#
# + calendarAvailabilities - the per-calendar availability results
# + return - the calendar addresses that reported an error, if any
function findUnreadableCalendars(CalendarAvailability[] calendarAvailabilities) returns string[] {
    return from CalendarAvailability calendarAvailability in calendarAvailabilities
        where calendarAvailability?.'error is string
        select calendarAvailability.calendar;
}

# Builds the attendee list for a booking: the room as a resource attendee plus everyone else as a regular invitee.
#
# + calendars - the participant calendar addresses (including the room)
# + roomCalendar - the room calendar address
# + return - the invitee addresses (excluding the room) and the full attendee list to send to Google
function buildAttendees(string[] calendars, string roomCalendar) returns [string[], gcalendar:EventAttendee[]] {
    string[] invitees = from string calendarId in calendars
        where calendarId != roomCalendar
        select calendarId;

    gcalendar:EventAttendee[] attendees = from string invitee in invitees
        select {email: invitee};
    attendees.push({email: roomCalendar, 'resource: true});

    return [invitees, attendees];
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

    string[] unreadableCalendars = findUnreadableCalendars(calendarAvailabilities);
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

    [string[], gcalendar:EventAttendee[]] [invitees, attendees] = buildAttendees(request.calendars, request.roomCalendar);

    gcalendar:Event newEvent = {
        summary: request.title,
        'start: {dateTime: fittingSlot.startTime},
        end: {dateTime: fittingSlot.endTime},
        attendees: attendees
    };

    gcalendar:Client activeCalendarClient = check getCalendarClient();
    gcalendar:Event _ = check activeCalendarClient->/calendars/[request.roomCalendar]/events.post(newEvent);

    return {
        booked: true,
        slot: fittingSlot,
        roomCalendar: request.roomCalendar,
        invitees: invitees,
        message: "booked the earliest available window"
    };
}

# Validates a recurring booking request, returning a message naming the broken rule if invalid.
#
# + request - the incoming recurring booking request
# + return - () if the request is valid, otherwise a message naming the rule that was broken
function validateRecurringBookingRequest(RecurringBookingRequest request) returns string? {
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

    if request.weekdays.length() == 0 {
        return "at least one weekday must be provided";
    }

    string? untilDate = request?.untilDate;
    int? occurrenceCount = request?.occurrenceCount;
    if untilDate is string && occurrenceCount is int {
        return "only one of untilDate or occurrenceCount must be provided, not both";
    }
    if untilDate is () && occurrenceCount is () {
        return "either untilDate or occurrenceCount must be provided";
    }
    if untilDate is string {
        time:Utc|time:Error untilDateUtc = time:utcFromString(untilDate);
        if untilDateUtc is time:Error {
            return "untilDate must be a valid RFC3339 timestamp";
        }
    }
    if occurrenceCount is int && occurrenceCount <= 0 {
        return "occurrenceCount must be greater than zero";
    }

    return ();
}

# Builds a weekly-recurrence RRULE string from the given weekdays and end condition.
#
# + weekdays - the days of the week the meeting repeats on
# + untilDate - the date after which the recurrence stops, in RFC3339 format, if given
# + occurrenceCount - the number of occurrences to repeat for, if given
# + return - the RRULE string, or an error if untilDate could not be parsed
function buildWeeklyRecurrenceRule(Weekday[] weekdays, string? untilDate, int? occurrenceCount) returns string|error {
    string byDay = string:'join(",", ...weekdays);
    if untilDate is string {
        time:Utc untilDateUtc = check time:utcFromString(untilDate);
        time:Civil untilCivil = time:utcToCivil(untilDateUtc);
        string untilStamp = string `${untilCivil.year}${padTwoDigits(untilCivil.month)}${padTwoDigits(untilCivil.day)}T235959Z`;
        return string `RRULE:FREQ=WEEKLY;BYDAY=${byDay};UNTIL=${untilStamp}`;
    }
    return string `RRULE:FREQ=WEEKLY;BYDAY=${byDay};COUNT=${occurrenceCount ?: 1}`;
}

# Pads a numeric date component to two digits.
#
# + value - the numeric component to pad
# + return - the two-digit, zero-padded representation
function padTwoDigits(int value) returns string {
    if value < 10 {
        return string `0${value}`;
    }
    return value.toString();
}

# Finds the earliest window in the requested period where every participant is free for the requested duration,
# and books it as a weekly-recurring meeting on the nominated room calendar, inviting the rest of the participants.
#
# + request - the recurring booking request
# + return - the recurring booking response (whether or not a fitting starting window was found), or an error if
# the calendar service could not be reached at all
function bookRecurringSlot(RecurringBookingRequest request) returns RecurringBookingResponse|error {
    string[] allCalendars = request.calendars;
    if allCalendars.indexOf(request.roomCalendar) is () {
        allCalendars = [...allCalendars, request.roomCalendar];
    }

    CalendarAvailability[] calendarAvailabilities = check queryCalendarAvailability(allCalendars, request.startTime, request.endTime);

    string[] unreadableCalendars = findUnreadableCalendars(calendarAvailabilities);
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

    string recurrenceRule = check buildWeeklyRecurrenceRule(request.weekdays, request?.untilDate, request?.occurrenceCount);

    [string[], gcalendar:EventAttendee[]] [invitees, attendees] = buildAttendees(request.calendars, request.roomCalendar);

    gcalendar:Event newEvent = {
        summary: request.title,
        'start: {dateTime: fittingSlot.startTime},
        end: {dateTime: fittingSlot.endTime},
        attendees: attendees,
        recurrence: [recurrenceRule]
    };

    gcalendar:Client activeCalendarClient = check getCalendarClient();
    gcalendar:Event createdEvent = check activeCalendarClient->/calendars/[request.roomCalendar]/events.post(newEvent);
    string? eventId = createdEvent.id;

    return {
        booked: true,
        slot: fittingSlot,
        roomCalendar: request.roomCalendar,
        invitees: invitees,
        eventId: eventId,
        recurrence: recurrenceRule,
        message: "booked the earliest available recurring window"
    };
}

# Validates an occurrence-listing request, returning a message naming the broken rule if invalid.
#
# + roomCalendar - the calendar address the recurring booking lives on
# + eventId - the identifier of the recurring booking
# + rangeStart - the start of the date range to list occurrences within, in RFC3339 format
# + rangeEnd - the end of the date range to list occurrences within, in RFC3339 format
# + return - () if the request is valid, otherwise a message naming the rule that was broken
function validateOccurrencesRequest(string roomCalendar, string eventId, string rangeStart, string rangeEnd) returns string? {
    if roomCalendar.trim().length() == 0 {
        return "roomCalendar must not be blank";
    }
    if eventId.trim().length() == 0 {
        return "eventId must not be blank";
    }

    time:Utc|time:Error rangeStartUtc = time:utcFromString(rangeStart);
    if rangeStartUtc is time:Error {
        return "rangeStart must be a valid RFC3339 timestamp";
    }

    time:Utc|time:Error rangeEndUtc = time:utcFromString(rangeEnd);
    if rangeEndUtc is time:Error {
        return "rangeEnd must be a valid RFC3339 timestamp";
    }

    if rangeEndUtc <= rangeStartUtc {
        return "rangeEnd must be after rangeStart";
    }

    return ();
}

# Lists the expanded occurrences of a recurring booking within a date range, so that occurrences moved or
# dropped from the original pattern are visible individually rather than just the repeating rule.
#
# + roomCalendar - the calendar address the recurring booking lives on
# + eventId - the identifier of the recurring booking
# + rangeStart - the start of the date range to list occurrences within, in RFC3339 format
# + rangeEnd - the end of the date range to list occurrences within, in RFC3339 format
# + return - the expanded occurrences, or an error if the calendar service could not be reached at all
function listBookingOccurrences(string roomCalendar, string eventId, string rangeStart, string rangeEnd) returns OccurrencesResponse|error {
    gcalendar:Client activeCalendarClient = check getCalendarClient();
    gcalendar:Events instancesResponse = check activeCalendarClient->/calendars/[roomCalendar]/events/[eventId]/instances(
        timeMin = rangeStart,
        timeMax = rangeEnd,
        showDeleted = true
    );

    gcalendar:Event[]? items = instancesResponse.items;
    Occurrence[] occurrences = [];
    if items is gcalendar:Event[] {
        foreach gcalendar:Event item in items {
            gcalendar:EventDateTime? occurrenceStart = item?.'start;
            gcalendar:EventDateTime? occurrenceEnd = item?.end;

            string? occurrenceStartTime = ();
            if occurrenceStart is gcalendar:EventDateTime {
                occurrenceStartTime = occurrenceStart.dateTime ?: occurrenceStart.date;
            }
            string? occurrenceEndTime = ();
            if occurrenceEnd is gcalendar:EventDateTime {
                occurrenceEndTime = occurrenceEnd.dateTime ?: occurrenceEnd.date;
            }

            occurrences.push({
                startTime: occurrenceStartTime,
                endTime: occurrenceEndTime,
                status: item.status ?: "confirmed"
            });
        }
    }

    return {occurrences: occurrences};
}

# Validates a move request, returning a message naming the broken rule if invalid.
#
# + request - the incoming move request
# + return - () if the request is valid, otherwise a message naming the rule that was broken
function validateMoveBookingRequest(MoveBookingRequest request) returns string? {
    if request.sourceCalendar.trim().length() == 0 {
        return "sourceCalendar must not be blank";
    }
    if request.eventId.trim().length() == 0 {
        return "eventId must not be blank";
    }
    if request.destinationCalendar.trim().length() == 0 {
        return "destinationCalendar must not be blank";
    }
    if request.destinationCalendar == request.sourceCalendar {
        return "destinationCalendar must be different from sourceCalendar";
    }
    return ();
}

# Relocates an existing booking from one room calendar to another.
#
# + request - the move request
# + return - the move response, or an error if the calendar service could not be reached at all
function moveBooking(MoveBookingRequest request) returns MoveBookingResponse|error {
    gcalendar:Client activeCalendarClient = check getCalendarClient();
    gcalendar:Event _ = check activeCalendarClient->/calendars/[request.sourceCalendar]/events/[request.eventId]/move.post(request.destinationCalendar);

    return {
        eventId: request.eventId,
        fromCalendar: request.sourceCalendar,
        toCalendar: request.destinationCalendar
    };
}

# Creates a calendar entry from a single line of free text on the nominated calendar.
#
# + request - the quick-capture request
# + return - the quick-capture response, or an error if the calendar service could not be reached at all
function quickCaptureEntry(QuickCaptureRequest request) returns QuickCaptureResponse|error {
    gcalendar:Client activeCalendarClient = check getCalendarClient();
    gcalendar:Event createdEvent = check activeCalendarClient->/calendars/[request.calendar]/events/quickAdd.post(request.text);

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
