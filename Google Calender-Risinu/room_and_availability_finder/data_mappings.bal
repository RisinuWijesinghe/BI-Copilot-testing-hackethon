import ballerinax/googleapis.gcalendar;

# Maps a Google freebusy error reason for a single calendar to our own wording.
#
# + reason - the reason code reported by Google for this calendar
# + return - a message describing the failure in our own wording
function toCalendarErrorMessage(string reason) returns string {
    match reason {
        "notFound" => {
            return "calendar was not found";
        }
        "forbidden" => {
            return "access to this calendar is not permitted";
        }
        _ => {
            return "calendar availability could not be retrieved";
        }
    }
}

# Converts a single calendar's freebusy result from the Google response into our own representation.
#
# + calendarId - the calendar address that was queried
# + freeBusyCalendar - the freebusy result reported by Google for this calendar
# + return - our own representation of the calendar's availability
function toCalendarAvailability(string calendarId, gcalendar:FreeBusyCalendar freeBusyCalendar) returns CalendarAvailability {
    gcalendar:ErrorDetails[]? calendarErrors = freeBusyCalendar.errors;
    if calendarErrors is gcalendar:ErrorDetails[] && calendarErrors.length() > 0 {
        string reason = calendarErrors[0].reason ?: "";
        return {
            calendar: calendarId,
            'error: toCalendarErrorMessage(reason)
        };
    }

    gcalendar:TimePeriod[]? busyPeriods = freeBusyCalendar.busy;
    BusyBlock[] busyBlocks = [];
    if busyPeriods is gcalendar:TimePeriod[] {
        foreach gcalendar:TimePeriod busyPeriod in busyPeriods {
            string? busyStart = busyPeriod?.'start;
            string? busyEnd = busyPeriod.end;
            if busyStart is string && busyEnd is string {
                busyBlocks.push({startTime: busyStart, endTime: busyEnd});
            }
        }
    }
    return {
        calendar: calendarId,
        busy: busyBlocks
    };
}
