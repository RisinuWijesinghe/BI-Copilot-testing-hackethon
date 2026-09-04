import ballerina/http;
import ballerina/test;
import ballerinax/aws.dynamodb;

// Startup's table-readiness check performs a real AWS call; it is replaced with a no-op for
// the test run so module initialization does not require live AWS access. The check itself
// is a thin wrapper over describeTable and is not the behaviour under test here.
@test:Mock {
    functionName: "ensureLeaderboardTableReady"
}
function mockEnsureLeaderboardTableReady() returns error? {
    return ();
}

final http:Client leaderboardClient = check new (string `http://localhost:${servicePort}/leaderboard`);

// ----------------------------------------------------------------------------------
// Score submission: a player's entry should only ever move up.
// ----------------------------------------------------------------------------------

@test:Config {}
function testFirstScoreForPlayerIsAccepted() returns error? {
    test:prepare(dynamoDbClient).when("updateItem").thenReturn(<dynamodb:ItemDescription>{});

    json payload = {playerName: "Alice", score: 100};
    ScoreAccepted response = check leaderboardClient->post("/games/space-invaders/scores", payload);

    test:assertEquals(response.playerName, "Alice", msg = "playerName should echo the submitted player");
    test:assertEquals(response.gameId, "space-invaders", msg = "gameId should echo the path parameter");
    test:assertEquals(response.score, 100d, msg = "score should echo the submitted score");
}

@test:Config {}
function testHigherScoreReplacesStoredBest() returns error? {
    test:prepare(dynamoDbClient).when("updateItem").thenReturn(<dynamodb:ItemDescription>{});

    json payload = {playerName: "Bob", score: 250};
    ScoreAccepted response = check leaderboardClient->post("/games/space-invaders/scores", payload);

    test:assertEquals(response.score, 250d, msg = "the new, higher score should be accepted");
}

@test:Config {}
function testLowerScoreDoesNotReplaceStoredBest() returns error? {
    // DynamoDB rejects the conditional update because the stored score is already >= the new one.
    dynamodb:Error conditionalFailure = error dynamodb:Error(
            "ConditionalCheckFailedException: The conditional request failed",
            httpStatusCode = 400);
    test:prepare(dynamoDbClient).when("updateItem").thenReturn(conditionalFailure);
    test:prepare(dynamoDbClient).when("query").thenReturn(mockQueryStreamWithScore("Carol", 500d));

    json payload = {playerName: "Carol", score: 300};
    ScoreNotImproved response = check leaderboardClient->post("/games/space-invaders/scores", payload);

    test:assertEquals(response.submittedScore, 300d, msg = "submittedScore should be the rejected score");
    test:assertEquals(response.bestScore, 500d, msg = "bestScore should be the previously stored best");
    test:assertEquals(response.playerName, "Carol", msg = "playerName should be echoed back");
}

// ----------------------------------------------------------------------------------
// Leaderboard reads: an unplayed game is an empty leaderboard, not an error.
// ----------------------------------------------------------------------------------

@test:Config {}
function testLeaderboardForUnplayedGameIsEmpty() returns error? {
    test:prepare(dynamoDbClient).when("query").thenReturn(mockEmptyQueryStream());

    Leaderboard response = check leaderboardClient->get("/games/never-played/scores?count=10");

    test:assertEquals(response.gameId, "never-played", msg = "gameId should echo the path parameter");
    test:assertEquals(response.scores, [], msg = "an unplayed game should return an empty score list");
}

@test:Config {}
function testLeaderboardReturnsTopScoresHighestFirst() returns error? {
    test:prepare(dynamoDbClient).when("query").thenReturn(mockQueryStreamWithEntries([
        {playerName: "Dave", score: 150d},
        {playerName: "Erin", score: 400d},
        {playerName: "Frank", score: 275d}
    ]));

    Leaderboard response = check leaderboardClient->get("/games/pac-man/scores?count=2");

    test:assertEquals(response.scores.length(), 2, msg = "only the requested count should be returned");
    test:assertEquals(response.scores[0], {playerName: "Erin", score: 400d}, msg = "highest score should be first");
    test:assertEquals(response.scores[1], {playerName: "Frank", score: 275d}, msg = "second highest should be next");
}

// ----------------------------------------------------------------------------------
// Single player lookup, rename, and removal: 404 when the player isn't on the board.
// ----------------------------------------------------------------------------------

@test:Config {}
function testGetPlayerStandingNotFoundIs404() returns error? {
    test:prepare(dynamoDbClient).when("getItem").thenReturn(<dynamodb:ItemGetOutput>{});

    http:Response response = check leaderboardClient->get("/games/space-invaders/players/Ghost");

    test:assertEquals(response.statusCode, 404, msg = "missing player lookup should be a 404");
}

@test:Config {}
function testGetPlayerStandingReturnsStoredScore() returns error? {
    test:prepare(dynamoDbClient).when("getItem").thenReturn(<dynamodb:ItemGetOutput>{
        Item: {
            "GameId": {S: "space-invaders"},
            "PlayerName": {S: "Grace"},
            "Score": {N: "620"}
        }
    });

    PlayerStanding response = check leaderboardClient->get("/games/space-invaders/players/Grace");

    test:assertEquals(response.playerName, "Grace", msg = "playerName should match the lookup");
    test:assertEquals(response.score, 620d, msg = "score should reflect the stored value");
}

@test:Config {}
function testRenameMissingPlayerIs404() returns error? {
    test:prepare(dynamoDbClient).when("getItem").thenReturn(<dynamodb:ItemGetOutput>{});

    json payload = {newPlayerName: "NewName"};
    http:Response response = check leaderboardClient->put("/games/space-invaders/players/Ghost/name", payload);

    test:assertEquals(response.statusCode, 404, msg = "renaming a missing player should be a 404");
}

@test:Config {}
function testRenameExistingPlayerReturnsPreviousName() returns error? {
    test:prepare(dynamoDbClient).when("getItem").thenReturn(<dynamodb:ItemGetOutput>{
        Item: {
            "GameId": {S: "space-invaders"},
            "PlayerName": {S: "Henry"},
            "Score": {N: "710"}
        }
    });
    test:prepare(dynamoDbClient).when("updateItem").thenReturn(<dynamodb:ItemDescription>{});
    test:prepare(dynamoDbClient).when("deleteItem").thenReturn(<dynamodb:ItemDescription>{});

    json payload = {newPlayerName: "HenryTheGreat"};
    NameChanged response = check leaderboardClient->put("/games/space-invaders/players/Henry/name", payload);

    test:assertEquals(response.previousPlayerName, "Henry", msg = "previous name should be reported");
    test:assertEquals(response.newPlayerName, "HenryTheGreat", msg = "new name should be applied");
    test:assertEquals(response.score, 710d, msg = "score should be preserved across the rename");
}

@test:Config {}
function testDeleteMissingPlayerIs404() returns error? {
    dynamodb:Error conditionalFailure = error dynamodb:Error(
            "ConditionalCheckFailedException: The conditional request failed",
            httpStatusCode = 400);
    test:prepare(dynamoDbClient).when("deleteItem").thenReturn(conditionalFailure);

    http:Response response = check leaderboardClient->delete("/games/space-invaders/players/Ghost");

    test:assertEquals(response.statusCode, 404, msg = "removing a missing player should be a 404");
}

@test:Config {}
function testDeleteExistingPlayerReturnsWhatWasStored() returns error? {
    test:prepare(dynamoDbClient).when("deleteItem").thenReturn(<dynamodb:ItemDescription>{
        Attributes: {
            "GameId": {S: "space-invaders"},
            "PlayerName": {S: "Ivy"},
            "Score": {N: "845"}
        }
    });

    PlayerRemoved response = check leaderboardClient->delete("/games/space-invaders/players/Ivy");

    test:assertEquals(response.playerName, "Ivy", msg = "removed player's name should be reported");
    test:assertEquals(response.score, 845d, msg = "removed player's score should reflect what was stored");
}

// ----------------------------------------------------------------------------------
// Input validation: 400s with nothing written.
// ----------------------------------------------------------------------------------

@test:Config {}
function testMissingPlayerNameIs400() returns error? {
    json payload = {score: 100};
    http:Response response = check leaderboardClient->post("/games/space-invaders/scores", payload);

    test:assertEquals(response.statusCode, 400, msg = "a missing playerName should be a 400");
}

@test:Config {}
function testNonNumericScoreIs400() returns error? {
    json payload = {playerName: "Jack", score: "not-a-number"};
    http:Response response = check leaderboardClient->post("/games/space-invaders/scores", payload);

    test:assertEquals(response.statusCode, 400, msg = "a non-numeric score should be a 400");
}

// ----------------------------------------------------------------------------------
// AWS failures never leak details into the response; a generic 502 is returned.
// ----------------------------------------------------------------------------------

@test:Config {}
function testAwsFailureOnScoreSubmissionIsGeneric502() returns error? {
    dynamodb:Error awsFailure = error dynamodb:Error(
            "AccessDeniedException: User arn:aws:iam::123456789012:user/svc is not authorized " +
            "to perform dynamodb:UpdateItem on resource GameLeaderboard",
            httpStatusCode = 403);
    test:prepare(dynamoDbClient).when("updateItem").thenReturn(awsFailure);

    json payload = {playerName: "Karen", score: 100};
    http:Response response = check leaderboardClient->post("/games/space-invaders/scores", payload);
    json responseBody = check response.getJsonPayload();
    string responseText = responseBody.toJsonString();

    test:assertEquals(response.statusCode, 502, msg = "an AWS failure should surface as a 502");
    test:assertTrue(!responseText.includes("AccessDeniedException"),
            msg = "the raw AWS error must not appear in the response");
    test:assertTrue(!responseText.includes(leaderboardTableName),
            msg = "the table name must not appear in the response");
    test:assertTrue(!responseText.includes("123456789012"),
            msg = "account details must not appear in the response");
}

@test:Config {}
function testAwsFailureOnLeaderboardReadIsGeneric502() returns error? {
    dynamodb:Error awsFailure = error dynamodb:Error(
            "ProvisionedThroughputExceededException on table GameLeaderboard in account 123456789012",
            httpStatusCode = 400);
    test:prepare(dynamoDbClient).when("query").thenReturn(awsFailure);

    http:Response response = check leaderboardClient->get("/games/space-invaders/scores?count=5");
    json responseBody = check response.getJsonPayload();
    string responseText = responseBody.toJsonString();

    test:assertEquals(response.statusCode, 502, msg = "an AWS failure should surface as a 502");
    test:assertTrue(!responseText.includes("GameLeaderboard"),
            msg = "the table name must not appear in the response");
    test:assertTrue(!responseText.includes("123456789012"),
            msg = "account details must not appear in the response");
    test:assertTrue(!responseText.includes("ProvisionedThroughputExceededException"),
            msg = "the raw AWS error code must not appear in the response");
}

// ----------------------------------------------------------------------------------
// Test helpers
// ----------------------------------------------------------------------------------

function mockEmptyQueryStream() returns stream<dynamodb:QueryOutput, dynamodb:Error?> {
    dynamodb:QueryOutput[] noResults = [];
    return noResults.toStream();
}

function mockQueryStreamWithScore(string playerName, decimal score) returns stream<dynamodb:QueryOutput, dynamodb:Error?> {
    dynamodb:QueryOutput[] results = [
        {
            Item: {
                "PlayerName": {S: playerName},
                "Score": {N: score.toString()}
            }
        }
    ];
    return results.toStream();
}

type MockLeaderboardEntry record {|
    string playerName;
    decimal score;
|};

function mockQueryStreamWithEntries(MockLeaderboardEntry[] entries) returns stream<dynamodb:QueryOutput, dynamodb:Error?> {
    dynamodb:QueryOutput[] results = from MockLeaderboardEntry entry in entries
        select {
            Item: {
                "PlayerName": {S: entry.playerName},
                "Score": {N: entry.score.toString()}
            }
        };
    return results.toStream();
}
