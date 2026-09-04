// Request payload for submitting a player's score.
public type ScoreSubmission record {|
    string playerName;
    decimal score;
|};

// A single leaderboard entry returned to the caller.
public type LeaderboardEntry record {|
    string playerName;
    decimal score;
|};

// Response for a successful score submission.
public type ScoreAccepted record {|
    string playerName;
    string gameId;
    decimal score;
|};

// Response when a submitted score does not beat the player's existing best.
public type ScoreNotImproved record {|
    string playerName;
    string gameId;
    decimal submittedScore;
    decimal bestScore;
    string message;
|};

// Response body for the top-scores leaderboard.
public type Leaderboard record {|
    string gameId;
    LeaderboardEntry[] scores;
|};

// Generic error message body.
public type ErrorDetail record {|
    string message;
|};
