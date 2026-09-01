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
