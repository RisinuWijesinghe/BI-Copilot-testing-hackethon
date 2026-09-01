// Request payload for creating a new shared calendar.
public type CreateCalendarRequest record {|
    string calendarName;
|};

// Response payload returned after a calendar is created.
public type CreateCalendarResponse record {|
    string calendarId;
|};

// Request payload for booking a meeting on a named calendar.
public type BookMeetingRequest record {|
    string title;
    string description?;
    string startTime;
    string endTime;
    string timeZone;
    string[] attendees;
|};

// Response payload returned after a meeting is successfully booked.
public type BookMeetingResponse record {|
    string eventId;
    string eventLink;
|};

// Plain-English error body returned to the caller for both validation and upstream failures.
public type ErrorDetails record {|
    string message;
|};

// A single occurrence on a calendar's agenda, carrying only what a UI needs to render it.
public type AgendaItem record {|
    string title;
    string startTime;
    string endTime;
    string location;
    string[] attendees;
|};

// Request payload for rescheduling an existing meeting to new start and end times.
public type RescheduleMeetingRequest record {|
    string startTime;
    string endTime;
    string timeZone;
|};

// Response payload returned after a meeting is successfully cancelled (including when
// it was already cancelled or never existed - the caller's desired outcome is already true).
public type CancelMeetingResponse record {|
    string message;
|};
