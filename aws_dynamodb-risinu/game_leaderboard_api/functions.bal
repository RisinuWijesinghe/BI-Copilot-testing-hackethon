import ballerina/log;
import ballerina/lang.runtime;
import ballerinax/aws.dynamodb;

const string GAME_ID_ATTR = "GameId";
const string PLAYER_NAME_ATTR = "PlayerName";
const string SCORE_ATTR = "Score";

// Signals that a requested player does not have an entry on the given game's leaderboard.
public type PlayerNotFoundError distinct error;

// Ensures the leaderboard table exists and is ACTIVE before the service starts serving traffic.
// If the table does not exist, it is created. Waits until the table becomes usable.
function ensureLeaderboardTableReady() returns error? {
    dynamodb:TableDescription|dynamodb:Error description = dynamoDbClient->describeTable(leaderboardTableName);
    if description is dynamodb:Error {
        log:printInfo("Leaderboard table not found, creating it", tableName = leaderboardTableName);
        dynamodb:TableDescription created = check dynamoDbClient->createTable({
            TableName: leaderboardTableName,
            AttributeDefinitions: [
                {AttributeName: GAME_ID_ATTR, AttributeType: dynamodb:S},
                {AttributeName: PLAYER_NAME_ATTR, AttributeType: dynamodb:S}
            ],
            KeySchema: [
                {AttributeName: GAME_ID_ATTR, KeyType: dynamodb:HASH},
                {AttributeName: PLAYER_NAME_ATTR, KeyType: dynamodb:RANGE}
            ],
            BillingMode: dynamodb:PAY_PER_REQUEST
        });
        description = created;
    }

    dynamodb:TableDescription tableDescription = check description;
    dynamodb:TableStatus? tableStatus = tableDescription?.TableStatus;
    while tableStatus != dynamodb:ACTIVE {
        runtime:sleep(2);
        dynamodb:TableDescription latest = check dynamoDbClient->describeTable(leaderboardTableName);
        tableStatus = latest?.TableStatus;
    }
    log:printInfo("Leaderboard table is ready", tableName = leaderboardTableName);
}

// Records a player's score for a game only if it improves on their existing best.
// Uses a conditional update expression so the write is rejected atomically when the
// stored score is already greater than or equal to the submitted score.
function recordScoreIfImproved(string gameId, string playerName, decimal score) returns boolean|error {
    string scoreValue = score.toString();
    dynamodb:ItemUpdateInput updateInput = {
        TableName: leaderboardTableName,
        Key: {
            [GAME_ID_ATTR]: {S: gameId},
            [PLAYER_NAME_ATTR]: {S: playerName}
        },
        UpdateExpression: "SET " + SCORE_ATTR + " = :newScore",
        ConditionExpression: "attribute_not_exists(" + SCORE_ATTR + ") OR " + SCORE_ATTR + " < :newScore",
        ExpressionAttributeValues: {
            ":newScore": {N: scoreValue}
        }
    };

    dynamodb:ItemDescription|dynamodb:Error result = dynamoDbClient->updateItem(updateInput);
    if result is dynamodb:Error {
        string errorMessage = result.message();
        if errorMessage.includes("ConditionalCheckFailedException") {
            return false;
        }
        return result;
    }
    return true;
}

// Retrieves the player's currently stored best score for a game, if any.
function getStoredBestScore(string gameId, string playerName) returns decimal?|error {
    stream<dynamodb:QueryOutput, dynamodb:Error?> items = check dynamoDbClient->query({
        TableName: leaderboardTableName,
        KeyConditionExpression: GAME_ID_ATTR + " = :gameId AND " + PLAYER_NAME_ATTR + " = :playerName",
        ExpressionAttributeValues: {
            ":gameId": {S: gameId},
            ":playerName": {S: playerName}
        }
    });

    decimal? bestScore = ();
    check from dynamodb:QueryOutput item in items
        do {
            map<dynamodb:AttributeValue> attributes = check item?.Item.ensureType();
            dynamodb:AttributeValue? scoreAttribute = attributes[SCORE_ATTR];
            if scoreAttribute is dynamodb:AttributeValue {
                string? scoreString = scoreAttribute?.N;
                if scoreString is string {
                    bestScore = check decimal:fromString(scoreString);
                }
            }
        };
    return bestScore;
}

// Retrieves all recorded scores for a game, highest first, limited to the requested count.
function getTopScores(string gameId, int count) returns LeaderboardEntry[]|error {
    stream<dynamodb:QueryOutput, dynamodb:Error?> items = check dynamoDbClient->query({
        TableName: leaderboardTableName,
        KeyConditionExpression: GAME_ID_ATTR + " = :gameId",
        ExpressionAttributeValues: {
            ":gameId": {S: gameId}
        }
    });

    LeaderboardEntry[] entries = [];
    check from dynamodb:QueryOutput item in items
        do {
            map<dynamodb:AttributeValue> attributes = check item?.Item.ensureType();
            dynamodb:AttributeValue? playerNameAttribute = attributes[PLAYER_NAME_ATTR];
            dynamodb:AttributeValue? scoreAttribute = attributes[SCORE_ATTR];
            if playerNameAttribute is dynamodb:AttributeValue && scoreAttribute is dynamodb:AttributeValue {
                string? playerName = playerNameAttribute?.S;
                string? scoreString = scoreAttribute?.N;
                if playerName is string && scoreString is string {
                    decimal score = check decimal:fromString(scoreString);
                    entries.push({playerName, score});
                }
            }
        };

    LeaderboardEntry[] sortedEntries = from LeaderboardEntry entry in entries
        order by entry.score descending
        select entry;

    if sortedEntries.length() > count {
        return sortedEntries.slice(0, count);
    }
    return sortedEntries;
}

// Retrieves a single player's standing for a game with a strongly consistent read, so a score
// posted moments ago is always reflected. Returns a PlayerNotFoundError if the player has no
// entry on that game's leaderboard.
function getPlayerStanding(string gameId, string playerName) returns PlayerStanding|PlayerNotFoundError|error {
    dynamodb:ItemGetOutput result = check dynamoDbClient->getItem({
        TableName: leaderboardTableName,
        Key: {
            [GAME_ID_ATTR]: {S: gameId},
            [PLAYER_NAME_ATTR]: {S: playerName}
        },
        ConsistentRead: true
    });

    map<dynamodb:AttributeValue>? item = result?.Item;
    if item is () {
        return error PlayerNotFoundError("Player not found on this game's leaderboard");
    }

    dynamodb:AttributeValue? scoreAttribute = item[SCORE_ATTR];
    if scoreAttribute is () {
        return error PlayerNotFoundError("Player not found on this game's leaderboard");
    }
    string? scoreString = scoreAttribute?.N;
    if scoreString is () {
        return error PlayerNotFoundError("Player not found on this game's leaderboard");
    }
    decimal score = check decimal:fromString(scoreString);
    return {gameId, playerName, score};
}

// Changes the display name shown on a game's leaderboard for a player, preserving their score.
// Since the player name is part of the table's key, the rename is performed by creating the
// entry under the new name and removing the old one. Returns a PlayerNotFoundError if the
// player has no existing entry on that game's leaderboard.
function renamePlayer(string gameId, string currentPlayerName, string newPlayerName)
        returns NameChanged|PlayerNotFoundError|error {
    PlayerStanding|PlayerNotFoundError|error currentStanding = getPlayerStanding(gameId, currentPlayerName);
    if currentStanding is PlayerNotFoundError {
        return currentStanding;
    }
    if currentStanding is error {
        return currentStanding;
    }

    decimal score = currentStanding.score;
    string scoreValue = score.toString();

    dynamodb:ItemUpdateInput createUnderNewName = {
        TableName: leaderboardTableName,
        Key: {
            [GAME_ID_ATTR]: {S: gameId},
            [PLAYER_NAME_ATTR]: {S: newPlayerName}
        },
        UpdateExpression: "SET " + SCORE_ATTR + " = :score",
        ExpressionAttributeValues: {
            ":score": {N: scoreValue}
        }
    };
    dynamodb:ItemDescription|dynamodb:Error createResult = dynamoDbClient->updateItem(createUnderNewName);
    if createResult is dynamodb:Error {
        return createResult;
    }

    dynamodb:ItemDeleteInput deleteOldName = {
        TableName: leaderboardTableName,
        Key: {
            [GAME_ID_ATTR]: {S: gameId},
            [PLAYER_NAME_ATTR]: {S: currentPlayerName}
        },
        ConditionExpression: "attribute_exists(" + SCORE_ATTR + ")"
    };
    dynamodb:ItemDescription|dynamodb:Error deleteResult = dynamoDbClient->deleteItem(deleteOldName);
    if deleteResult is dynamodb:Error {
        string errorMessage = deleteResult.message();
        if errorMessage.includes("ConditionalCheckFailedException") {
            return error PlayerNotFoundError("Player not found on this game's leaderboard");
        }
        return deleteResult;
    }

    return {gameId, previousPlayerName: currentPlayerName, newPlayerName, score};
}

// Removes a player's entry from a game's leaderboard entirely, returning what was stored
// before deletion. Returns a PlayerNotFoundError if the player has no existing entry.
function removePlayer(string gameId, string playerName) returns PlayerRemoved|PlayerNotFoundError|error {
    dynamodb:ItemDeleteInput deleteInput = {
        TableName: leaderboardTableName,
        Key: {
            [GAME_ID_ATTR]: {S: gameId},
            [PLAYER_NAME_ATTR]: {S: playerName}
        },
        ConditionExpression: "attribute_exists(" + SCORE_ATTR + ")",
        ReturnValues: dynamodb:ALL_OLD
    };

    dynamodb:ItemDescription|dynamodb:Error result = dynamoDbClient->deleteItem(deleteInput);
    if result is dynamodb:Error {
        string errorMessage = result.message();
        if errorMessage.includes("ConditionalCheckFailedException") {
            return error PlayerNotFoundError("Player not found on this game's leaderboard");
        }
        return result;
    }

    map<dynamodb:AttributeValue>? attributes = result?.Attributes;
    decimal score = 0d;
    if attributes is map<dynamodb:AttributeValue> {
        dynamodb:AttributeValue? scoreAttribute = attributes[SCORE_ATTR];
        if scoreAttribute is dynamodb:AttributeValue {
            string? scoreString = scoreAttribute?.N;
            if scoreString is string {
                score = check decimal:fromString(scoreString);
            }
        }
    }

    return {gameId, playerName, score};
}

// Lists the leaderboard tables visible to this deployment's AWS account.
function listLeaderboardTables() returns string[]|error {
    stream<string, dynamodb:Error?> tableNames = check dynamoDbClient->listTables();
    string[] tables = check from string tableName in tableNames
        select tableName;
    return tables;
}
