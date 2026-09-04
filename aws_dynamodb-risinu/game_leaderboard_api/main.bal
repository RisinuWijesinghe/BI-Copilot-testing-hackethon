import ballerina/http;
import ballerina/log;

listener http:Listener leaderboardListener = new (servicePort);

function init() returns error? {
    // The service must not start serving traffic until the leaderboard storage is confirmed usable.
    check ensureLeaderboardTableReady();
}

service /leaderboard on leaderboardListener {

    // Submits a player's score for a game. Only updates the stored score if it is a new best.
    resource function post games/[string gameId]/scores(@http:Payload json payload)
            returns ScoreAccepted|ScoreNotImproved|http:BadRequest|http:BadGateway {
        json|error playerNameJson = trap payload.playerName;
        string playerName;
        if playerNameJson is error || playerNameJson !is string || playerNameJson.trim().length() == 0 {
            return <http:BadRequest>{
                body: {message: "playerName is required and must be a non-empty string"}
            };
        }
        playerName = playerNameJson;

        json|error scoreJson = trap payload.score;
        if scoreJson is error || (scoreJson !is int && scoreJson !is float && scoreJson !is decimal) {
            return <http:BadRequest>{
                body: {message: "score is required and must be a number"}
            };
        }
        decimal|error scoreConversion = decimal:fromString(scoreJson.toString());
        if scoreConversion is error {
            return <http:BadRequest>{
                body: {message: "score is required and must be a number"}
            };
        }
        decimal score = scoreConversion;

        boolean|error updateResult = recordScoreIfImproved(gameId, playerName, score);
        if updateResult is error {
            log:printError("Failed to record score in DynamoDB", updateResult,
                    gameId = gameId, playerName = playerName, tableName = leaderboardTableName);
            return <http:BadGateway>{
                body: {message: "Unable to reach the leaderboard storage right now. Please try again later."}
            };
        }

        if updateResult {
            return <ScoreAccepted>{
                playerName,
                gameId,
                score
            };
        }

        decimal?|error bestScoreResult = getStoredBestScore(gameId, playerName);
        if bestScoreResult is error {
            log:printError("Failed to fetch stored best score from DynamoDB", bestScoreResult,
                    gameId = gameId, playerName = playerName, tableName = leaderboardTableName);
            return <http:BadGateway>{
                body: {message: "Unable to reach the leaderboard storage right now. Please try again later."}
            };
        }

        decimal bestScore = bestScoreResult ?: score;
        return <ScoreNotImproved>{
            playerName,
            gameId,
            submittedScore: score,
            bestScore,
            message: "Submitted score did not beat the existing best score"
        };
    }

    // Returns the top scores for a game, highest first. An unplayed game returns an empty leaderboard.
    resource function get games/[string gameId]/scores(int count)
            returns Leaderboard|http:BadRequest|http:BadGateway {
        if count <= 0 {
            return <http:BadRequest>{
                body: {message: "count must be a positive number"}
            };
        }

        LeaderboardEntry[]|error topScores = getTopScores(gameId, count);
        if topScores is error {
            log:printError("Failed to query leaderboard from DynamoDB", topScores,
                    gameId = gameId, tableName = leaderboardTableName);
            return <http:BadGateway>{
                body: {message: "Unable to reach the leaderboard storage right now. Please try again later."}
            };
        }

        return <Leaderboard>{
            gameId,
            scores: topScores
        };
    }

    // Looks up a single player's standing in a game directly, without pulling the whole board.
    // Uses a strongly consistent read so a score posted moments ago is always reflected.
    resource function get games/[string gameId]/players/[string playerName]()
            returns PlayerStanding|http:NotFound|http:BadGateway {
        PlayerStanding|PlayerNotFoundError|error standing = getPlayerStanding(gameId, playerName);
        if standing is PlayerNotFoundError {
            return <http:NotFound>{
                body: {message: "Player not found on this game's leaderboard"}
            };
        }
        if standing is error {
            log:printError("Failed to fetch player standing from DynamoDB", standing,
                    gameId = gameId, playerName = playerName, tableName = leaderboardTableName);
            return <http:BadGateway>{
                body: {message: "Unable to reach the leaderboard storage right now. Please try again later."}
            };
        }
        return standing;
    }

    // Changes the display name shown on a game's leaderboard for a player. Reports the previous
    // name on success. Renaming a player who isn't on that board is a 404, not a silent success.
    resource function put games/[string gameId]/players/[string playerName]/name(@http:Payload json payload)
            returns NameChanged|http:BadRequest|http:NotFound|http:BadGateway {
        json|error newPlayerNameJson = trap payload.newPlayerName;
        if newPlayerNameJson is error || newPlayerNameJson !is string || newPlayerNameJson.trim().length() == 0 {
            return <http:BadRequest>{
                body: {message: "newPlayerName is required and must be a non-empty string"}
            };
        }
        string newPlayerName = newPlayerNameJson;

        NameChanged|PlayerNotFoundError|error result = renamePlayer(gameId, playerName, newPlayerName);
        if result is PlayerNotFoundError {
            return <http:NotFound>{
                body: {message: "Player not found on this game's leaderboard"}
            };
        }
        if result is error {
            log:printError("Failed to rename player in DynamoDB", result,
                    gameId = gameId, playerName = playerName, tableName = leaderboardTableName);
            return <http:BadGateway>{
                body: {message: "Unable to reach the leaderboard storage right now. Please try again later."}
            };
        }
        return result;
    }

    // Removes a player from a game's leaderboard entirely, reporting what was stored before
    // removal. Removing a player who isn't on that board is a 404, not a silent success.
    resource function delete games/[string gameId]/players/[string playerName]()
            returns PlayerRemoved|http:NotFound|http:BadGateway {
        PlayerRemoved|PlayerNotFoundError|error result = removePlayer(gameId, playerName);
        if result is PlayerNotFoundError {
            return <http:NotFound>{
                body: {message: "Player not found on this game's leaderboard"}
            };
        }
        if result is error {
            log:printError("Failed to remove player in DynamoDB", result,
                    gameId = gameId, playerName = playerName, tableName = leaderboardTableName);
            return <http:BadGateway>{
                body: {message: "Unable to reach the leaderboard storage right now. Please try again later."}
            };
        }
        return result;
    }
}
