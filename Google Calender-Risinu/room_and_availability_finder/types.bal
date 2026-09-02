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

# Days of the week a recurring booking can repeat on.
public type Weekday "MO"|"TU"|"WE"|"TH"|"FR"|"SA"|"SU";

# Request body for finding and booking the earliest common free slot as a weekly-recurring meeting.
public type RecurringBookingRequest record {|
    # Calendar addresses (people or rooms) that must all be free
    string[] calendars;
    # Start of the period to search within for the first occurrence, in RFC3339 format
    string startTime;
    # End of the period to search within for the first occurrence, in RFC3339 format
    string endTime;
    # Length of each occurrence, in minutes
    int durationMinutes;
    # Title of the meeting
    string title;
    # Calendar address of the room to book the meeting on
    string roomCalendar;
    # Days of the week the meeting repeats on
    Weekday[] weekdays;
    # Date (RFC3339) after which the recurrence stops. Exactly one of untilDate/occurrenceCount must be given
    string untilDate?;
    # Number of occurrences to repeat for. Exactly one of untilDate/occurrenceCount must be given
    int occurrenceCount?;
|};

# Successful response body for a recurring booking request, whether or not a starting slot was found.
public type RecurringBookingResponse record {|
    # Whether a fitting starting window was found and the recurring meeting was booked
    boolean booked;
    # The window that was booked for the first occurrence, if any
    FreeSlot? slot = ();
    # The room the meeting was booked on, if any
    string? roomCalendar = ();
    # The participants invited, if any
    string[]? invitees = ();
    # The identifier of the created recurring booking, if any
    string? eventId = ();
    # The recurrence rule that was applied, if any
    string? recurrence = ();
    # A human-readable explanation, especially useful when nothing was booked
    string message;
|};

# One expanded occurrence of a recurring booking.
public type Occurrence record {|
    # Start of this occurrence, in RFC3339 format
    string? startTime = ();
    # End of this occurrence, in RFC3339 format
    string? endTime = ();
    # The status of this occurrence, e.g. "confirmed" or "cancelled" (dropped)
    string status;
|};

# Response body listing the expanded occurrences of a recurring booking within a date range.
public type OccurrencesResponse record {|
    Occurrence[] occurrences;
|};

# Request body for relocating an existing booking from one room calendar to another.
public type MoveBookingRequest record {|
    # Calendar address the booking currently lives on
    string sourceCalendar;
    # Identifier of the event to relocate
    string eventId;
    # Calendar address to move the booking to
    string destinationCalendar;
|};

# Successful response body for a move request.
public type MoveBookingResponse record {|
    # Identifier of the moved event
    string eventId;
    # The calendar the booking moved from
    string fromCalendar;
    # The calendar the booking now lives on
    string toCalendar;
|};
