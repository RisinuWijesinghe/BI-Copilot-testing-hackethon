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

// Response for a single player's standing in a game.
public type PlayerStanding record {|
    string gameId;
    string playerName;
    decimal score;
|};

// Response for a successful display name change, including the previous name.
public type NameChanged record {|
    string gameId;
    string previousPlayerName;
    string newPlayerName;
    decimal score;
|};

// Response for a successful removal, including what was stored before deletion.
public type PlayerRemoved record {|
    string gameId;
    string playerName;
    decimal score;
|};

