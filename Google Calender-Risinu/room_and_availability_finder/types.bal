# Request body for the availability lookup.
public type AvailabilityRequest record {|
    # Calendar addresses (people or rooms) to check
    string[] calendars;
    # Start of the period to check, in RFC3339 format
    string startTime;
    # End of the period to check, in RFC3339 format
    string endTime;
|};

# A single occupied block of time on a calendar.
public type BusyBlock record {|
    string startTime;
    string endTime;
|};

# A gap during which every requested calendar is simultaneously free.
public type FreeSlot record {|
    string startTime;
    string endTime;
|};

# The busy information (or error) for one requested calendar.
public type CalendarAvailability record {|
    string calendar;
    BusyBlock[] busy?;
    string 'error?;
|};

# Successful response body for the availability lookup.
public type AvailabilityResponse record {|
    CalendarAvailability[] calendars;
    FreeSlot[] commonFreeSlots;
|};

# Body returned for a bad request, naming the rule that was broken.
public type ValidationErrorBody record {|
    string message;
|};

# Body returned when the calendar service cannot be reached at all.
public type UpstreamErrorBody record {|
    string message;
|};

# Request body for finding and booking the earliest common free slot.
public type BookingRequest record {|
    # Calendar addresses (people or rooms) that must all be free
    string[] calendars;
    # Start of the period to search within, in RFC3339 format
    string startTime;
    # End of the period to search within, in RFC3339 format
    string endTime;
    # Length of the meeting, in minutes
    int durationMinutes;
    # Title of the meeting
    string title;
    # Calendar address of the room to book the meeting on
    string roomCalendar;
|};

# Successful response body for a booking request, whether or not a slot was found.
public type BookingResponse record {|
    # Whether a fitting window was found and booked
    boolean booked;
    # The window that was booked, if any
    FreeSlot? slot = ();
    # The room the meeting was booked on, if any
    string? roomCalendar = ();
    # The participants invited, if any
    string[]? invitees = ();
    # A human-readable explanation, especially useful when nothing was booked
    string message;
|};

# Request body for the quick-capture endpoint.
public type QuickCaptureRequest record {|
    # Calendar address to create the entry on
    string calendar;
    # A single line of free text describing the event, e.g. "Coffee with Priya Thursday 3pm"
    string text;
|};

# Successful response body for the quick-capture endpoint.
public type QuickCaptureResponse record {|
    # The calendar the entry was created on
    string calendar;
    # The title Google Calendar derived for the event
    string title;
    # Start of the created event, in RFC3339 format, if known
    string? startTime = ();
    # End of the created event, in RFC3339 format, if known
    string? endTime = ();
|};
