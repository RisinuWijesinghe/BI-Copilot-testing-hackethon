import ballerina/test;
import ballerinax/aws.sns;

// ---- Email validation ----

@test:Config {}
function testIsValidEmailAcceptsUsableEmail() {
    boolean result = isValidEmail("fan@example.com");
    test:assertTrue(result, "expected a well-formed email to be considered valid");
}

@test:Config {}
function testIsValidEmailRejectsUnusableEmail() {
    boolean result = isValidEmail("not-an-email");
    test:assertTrue(!result, "expected a malformed email to be rejected");
}

// ---- Subscribing ----

@test:Config {}
function testSubscribeFanSuccess() returns error? {
    test:MockObject mockSns = test:prepare(snsClient);
    mockSns.when("subscribe").thenReturn("arn:aws:sns:us-east-1:123456789012:sub-1");
    snsClient = <sns:Client>mockSns;

    SubscriptionResult result = check subscribeFanToMatchAlerts("fan@example.com");

    test:assertEquals(result.email, "fan@example.com", msg = "email should be echoed back");
    test:assertEquals(result.status, "subscription pending confirmation", msg = "unexpected status");
    test:assertTrue(result.subscriberId.length() > 0, "expected a non-empty subscriber id");
}

@test:Config {}
function testSubscribeFanSnsFailureReturnsCleanError() {
    test:MockObject mockSns = test:prepare(snsClient);
    sns:Error snsError = error sns:Error("internal aws failure: access denied");
    mockSns.when("subscribe").thenReturn(snsError);
    snsClient = <sns:Client>mockSns;

    SubscriptionResult|error result = subscribeFanToMatchAlerts("fan@example.com");

    test:assertTrue(result is error, "expected an error when SNS subscribe fails");
    if result is error {
        string errorMessage = result.message();
        test:assertEquals(errorMessage, "Unable to complete the subscription at this time. Please try again later.",
                msg = "error message should be a clean, generic failure and not leak AWS details");
    }
}

// ---- Sending a batch of alerts ----

@test:Config {}
function testBroadcastMatchAlertsBatchSuccess() returns error? {
    test:MockObject mockSns = test:prepare(snsClient);
    sns:PublishBatchResponse batchResponse = {
        successful: [
            {id: "kickoff", messageId: "msg-1"},
            {id: "goal", messageId: "msg-2"},
            {id: "fulltime", messageId: "msg-3"}
        ],
        failed: []
    };
    mockSns.when("publishBatch").thenReturn(batchResponse);
    snsClient = <sns:Client>mockSns;

    AlertItem[] alerts = [
        {id: "kickoff", message: "Kick-off!"},
        {id: "goal", message: "Goal scored!"},
        {id: "fulltime", message: "Full-time."}
    ];
    AlertOutcome[] outcomes = check broadcastMatchAlerts(alerts);

    test:assertEquals(outcomes.length(), 3, msg = "expected an outcome for each alert in the batch");
    foreach AlertOutcome outcome in outcomes {
        test:assertEquals(outcome.status, "alert sent", msg = "expected every alert to have been sent");
    }
}

@test:Config {}
function testBroadcastMatchAlertsPartialFailure() returns error? {
    test:MockObject mockSns = test:prepare(snsClient);
    sns:PublishBatchResponse batchResponse = {
        successful: [
            {id: "kickoff", messageId: "msg-1"}
        ],
        failed: [
            {code: "InternalError", id: "goal", senderFault: false, message: "internal aws failure"}
        ]
    };
    mockSns.when("publishBatch").thenReturn(batchResponse);
    snsClient = <sns:Client>mockSns;

    AlertItem[] alerts = [
        {id: "kickoff", message: "Kick-off!"},
        {id: "goal", message: "Goal scored!"}
    ];
    AlertOutcome[] outcomes = check broadcastMatchAlerts(alerts);

    test:assertEquals(outcomes.length(), 2, msg = "expected an outcome for each alert in the batch");

    AlertOutcome[] sentOutcomes = from AlertOutcome outcome in outcomes
        where outcome.id == "kickoff"
        select outcome;
    test:assertEquals(sentOutcomes.length(), 1, msg = "expected the kickoff alert to be present");
    test:assertEquals(sentOutcomes[0].status, "alert sent", msg = "expected the kickoff alert to have been sent");

    AlertOutcome[] failedOutcomes = from AlertOutcome outcome in outcomes
        where outcome.id == "goal"
        select outcome;
    test:assertEquals(failedOutcomes.length(), 1, msg = "expected the goal alert to be present");
    test:assertEquals(failedOutcomes[0].status, "alert failed", msg = "expected the goal alert to have failed");
    string? failedErrorMessage = failedOutcomes[0].errorMessage;
    test:assertTrue(failedErrorMessage is string, "expected a clean error message on the failed alert");
    if failedErrorMessage is string {
        test:assertTrue(!failedErrorMessage.includes("aws"),
                "failed alert error message should not leak internal AWS error details");
    }
}

@test:Config {}
function testBroadcastMatchAlertsTotalSnsFailureReturnsCleanError() {
    test:MockObject mockSns = test:prepare(snsClient);
    sns:Error snsError = error sns:Error("internal aws failure: throttled");
    mockSns.when("publishBatch").thenReturn(snsError);
    snsClient = <sns:Client>mockSns;

    AlertItem[] alerts = [
        {id: "kickoff", message: "Kick-off!"}
    ];
    AlertOutcome[]|error result = broadcastMatchAlerts(alerts);

    test:assertTrue(result is error, "expected an error when the whole batch publish call fails");
    if result is error {
        string errorMessage = result.message();
        test:assertEquals(errorMessage, "Unable to send the alerts at this time. Please try again later.",
                msg = "error message should be a clean, generic failure and not leak AWS details");
    }
}

// ---- Unsubscribing ----

@test:Config {}
function testUnsubscribeFanNotFound() returns error? {
    boolean result = check unsubscribeFan("some-id-that-does-not-exist");
    test:assertTrue(!result, "expected unsubscribe to report false for an unknown subscriber id");
}

@test:Config {}
function testUnsubscribeFanSuccess() returns error? {
    string subscriberId = "test-subscriber-1";
    subscriberRegistry[subscriberId] = {
        subscriberId,
        email: "fan@example.com",
        subscriptionArn: "arn:aws:sns:us-east-1:123456789012:sub-1"
    };

    test:MockObject mockSns = test:prepare(snsClient);
    mockSns.when("unsubscribe").thenReturn(());
    snsClient = <sns:Client>mockSns;

    boolean result = check unsubscribeFan(subscriberId);

    test:assertTrue(result, "expected unsubscribe to succeed for a known subscriber id");
    test:assertTrue(!subscriberRegistry.hasKey(subscriberId), "expected the subscriber to be removed from the registry");
}

@test:Config {}
function testUnsubscribeFanSnsFailureReturnsCleanError() {
    string subscriberId = "test-subscriber-2";
    subscriberRegistry[subscriberId] = {
        subscriberId,
        email: "fan2@example.com",
        subscriptionArn: "arn:aws:sns:us-east-1:123456789012:sub-2"
    };

    test:MockObject mockSns = test:prepare(snsClient);
    sns:Error snsError = error sns:Error("internal aws failure: not authorized");
    mockSns.when("unsubscribe").thenReturn(snsError);
    snsClient = <sns:Client>mockSns;

    boolean|error result = unsubscribeFan(subscriberId);

    test:assertTrue(result is error, "expected an error when SNS unsubscribe fails");
    if result is error {
        string errorMessage = result.message();
        test:assertEquals(errorMessage, "Unable to unsubscribe at this time. Please try again later.",
                msg = "error message should be a clean, generic failure and not leak AWS details");
    }
    test:assertTrue(subscriberRegistry.hasKey(subscriberId),
            "expected the subscriber to remain in the registry since the unsubscribe failed");
}
