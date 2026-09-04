import ballerina/test;
import ballerinax/aws.dynamodbstreams;

function stringAttribute(string value) returns dynamodbstreams:AttributeValue {
    return {s: value};
}

@test:Config {}
function testIsTestStatusRecognizesTestPrefix() {
    test:assertTrue(isTestStatus("TEST_CANCELLED"), msg = "a status starting with TEST_ should be recognized");
}

@test:Config {}
function testIsTestStatusRejectsRealStatus() {
    test:assertFalse(isTestStatus("CANCELLED"), msg = "a normal status should not be treated as a test marker");
}

@test:Config {}
function testIsTestStatusIsCaseSensitivePrefixCheck() {
    test:assertFalse(isTestStatus("test_cancelled"), msg = "the prefix check should not match a different case");
}

@test:Config {}
function testNarrateInsertProducesOrderPlaced() {
    dynamodbstreams:Record changeRecord = {
        eventID: "evt-1",
        eventName: dynamodbstreams:INSERT,
        dynamodb: {
            keys: {OrderId: stringAttribute("order-1")},
            newImage: {OrderId: stringAttribute("order-1"), Status: stringAttribute("PLACED")}
        }
    };

    OrderChangeNarration? narration = narrateChangeRecord(changeRecord);
    test:assertTrue(narration is OrderChangeNarration, msg = "a well-formed INSERT should be narrated");
    if narration is OrderChangeNarration {
        test:assertEquals(narration.kind, ORDER_PLACED, msg = "an INSERT should be an order placed narration");
        test:assertEquals(narration.orderId, "order-1", msg = "the order id should be extracted from the keys");
        test:assertEquals(narration?.newStatus, "PLACED", msg = "the new status should be extracted from the new image");
        test:assertTrue(narration?.previousStatus is (), msg = "an order placed narration should have no previous status");
    }
}

@test:Config {}
function testNarrateInsertSkipsTestStatus() {
    dynamodbstreams:Record changeRecord = {
        eventID: "evt-2",
        eventName: dynamodbstreams:INSERT,
        dynamodb: {
            keys: {OrderId: stringAttribute("order-2")},
            newImage: {OrderId: stringAttribute("order-2"), Status: stringAttribute("TEST_PLACED")}
        }
    };

    OrderChangeNarration? narration = narrateChangeRecord(changeRecord);
    test:assertTrue(narration is (), msg = "an order with an internal test status marker should be skipped");
}

@test:Config {}
function testNarrateInsertMissingStatusIsSkipped() {
    dynamodbstreams:Record changeRecord = {
        eventID: "evt-3",
        eventName: dynamodbstreams:INSERT,
        dynamodb: {
            keys: {OrderId: stringAttribute("order-3")},
            newImage: {OrderId: stringAttribute("order-3")}
        }
    };

    OrderChangeNarration? narration = narrateChangeRecord(changeRecord);
    test:assertTrue(narration is (), msg = "an INSERT missing the status attribute should be skipped, not fatal");
}

@test:Config {}
function testNarrateModifyProducesStatusChanged() {
    dynamodbstreams:Record changeRecord = {
        eventID: "evt-4",
        eventName: dynamodbstreams:MODIFY,
        dynamodb: {
            keys: {OrderId: stringAttribute("order-4")},
            oldImage: {OrderId: stringAttribute("order-4"), Status: stringAttribute("PLACED")},
            newImage: {OrderId: stringAttribute("order-4"), Status: stringAttribute("SHIPPED")}
        }
    };

    OrderChangeNarration? narration = narrateChangeRecord(changeRecord);
    test:assertTrue(narration is OrderChangeNarration, msg = "a well-formed MODIFY should be narrated");
    if narration is OrderChangeNarration {
        test:assertEquals(narration.kind, ORDER_STATUS_CHANGED, msg = "a MODIFY should be a status changed narration");
        test:assertEquals(narration?.previousStatus, "PLACED", msg = "the previous status should come from the old image");
        test:assertEquals(narration?.newStatus, "SHIPPED", msg = "the new status should come from the new image");
    }
}

@test:Config {}
function testNarrateModifySkipsWhenEitherSideIsTestStatus() {
    dynamodbstreams:Record changeRecord = {
        eventID: "evt-5",
        eventName: dynamodbstreams:MODIFY,
        dynamodb: {
            keys: {OrderId: stringAttribute("order-5")},
            oldImage: {OrderId: stringAttribute("order-5"), Status: stringAttribute("TEST_PLACED")},
            newImage: {OrderId: stringAttribute("order-5"), Status: stringAttribute("SHIPPED")}
        }
    };

    OrderChangeNarration? narration = narrateChangeRecord(changeRecord);
    test:assertTrue(narration is (), msg = "a MODIFY touching a test status on either side should be skipped");
}

@test:Config {}
function testNarrateRemoveProducesOrderRemovedWithNoSpecialCasing() {
    dynamodbstreams:Record changeRecord = {
        eventID: "evt-6",
        eventName: dynamodbstreams:REMOVE,
        dynamodb: {
            keys: {OrderId: stringAttribute("order-6")},
            oldImage: {OrderId: stringAttribute("order-6"), Status: stringAttribute("SHIPPED")}
        },
        userIdentity: {principalId: "dynamodb.amazonaws.com", 'type: "Service"}
    };

    OrderChangeNarration? narration = narrateChangeRecord(changeRecord);
    test:assertTrue(narration is OrderChangeNarration, msg = "a well-formed REMOVE should be narrated");
    if narration is OrderChangeNarration {
        test:assertEquals(narration.kind, ORDER_REMOVED,
                msg = "every REMOVE should be a single order removed kind regardless of what caused it");
        test:assertEquals(narration?.previousStatus, "SHIPPED", msg = "the previous status should come from the old image");
    }
}

@test:Config {}
function testNarrateRemoveWithoutOldImageStillProducesNarration() {
    dynamodbstreams:Record changeRecord = {
        eventID: "evt-7",
        eventName: dynamodbstreams:REMOVE,
        dynamodb: {
            keys: {OrderId: stringAttribute("order-7")}
        }
    };

    OrderChangeNarration? narration = narrateChangeRecord(changeRecord);
    test:assertTrue(narration is OrderChangeNarration, msg = "a REMOVE without an old image should still be narrated");
    if narration is OrderChangeNarration {
        test:assertEquals(narration.kind, ORDER_REMOVED, msg = "it should still be an order removed narration");
        test:assertTrue(narration?.previousStatus is (), msg = "no previous status should be present");
    }
}

@test:Config {}
function testNarrateRemoveSkipsTestStatus() {
    dynamodbstreams:Record changeRecord = {
        eventID: "evt-8",
        eventName: dynamodbstreams:REMOVE,
        dynamodb: {
            keys: {OrderId: stringAttribute("order-8")},
            oldImage: {OrderId: stringAttribute("order-8"), Status: stringAttribute("TEST_SHIPPED")}
        }
    };

    OrderChangeNarration? narration = narrateChangeRecord(changeRecord);
    test:assertTrue(narration is (), msg = "a REMOVE of an order with a test status marker should be skipped");
}

@test:Config {}
function testNarrateReturnsNilWhenOrderIdMissing() {
    dynamodbstreams:Record changeRecord = {
        eventID: "evt-9",
        eventName: dynamodbstreams:INSERT,
        dynamodb: {
            keys: {},
            newImage: {Status: stringAttribute("PLACED")}
        }
    };

    OrderChangeNarration? narration = narrateChangeRecord(changeRecord);
    test:assertTrue(narration is (), msg = "a record missing the order id key should be skipped, not fatal");
}

@test:Config {}
function testNarrateReturnsNilWhenDynamoDbSectionMissing() {
    dynamodbstreams:Record changeRecord = {
        eventID: "evt-10",
        eventName: dynamodbstreams:INSERT
    };

    OrderChangeNarration? narration = narrateChangeRecord(changeRecord);
    test:assertTrue(narration is (), msg = "a record missing the dynamodb section entirely should be skipped");
}

@test:Config {}
function testRenderNarrationForOrderPlaced() {
    string line = renderNarration({kind: ORDER_PLACED, orderId: "order-1", newStatus: "PLACED"});
    test:assertEquals(line, "Order order-1 was placed with status PLACED");
}

@test:Config {}
function testRenderNarrationForStatusChanged() {
    string line = renderNarration({kind: ORDER_STATUS_CHANGED, orderId: "order-2", previousStatus: "PLACED", newStatus: "SHIPPED"});
    test:assertEquals(line, "Order order-2 moved from PLACED to SHIPPED");
}

@test:Config {}
function testRenderNarrationForRemovedWithPreviousStatus() {
    string line = renderNarration({kind: ORDER_REMOVED, orderId: "order-3", previousStatus: "SHIPPED"});
    test:assertEquals(line, "Order order-3 is gone (was SHIPPED)");
}

@test:Config {}
function testRenderNarrationForRemovedWithoutPreviousStatus() {
    string line = renderNarration({kind: ORDER_REMOVED, orderId: "order-4"});
    test:assertEquals(line, "Order order-4 is gone");
}
