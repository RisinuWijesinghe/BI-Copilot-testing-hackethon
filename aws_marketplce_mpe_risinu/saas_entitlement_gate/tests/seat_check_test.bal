import ballerina/http;
import ballerina/test;
import ballerina/time;
import ballerinax/aws.marketplace.mpe;

const string ENTITLED_CUSTOMER = "entitled-customer";
const string OVER_ASKING_CUSTOMER = "over-asking-customer";
const string EXPIRED_CUSTOMER = "expired-customer";
const string UNKNOWN_CUSTOMER = "unknown-customer";
const string AWS_DOWN_CUSTOMER = "aws-down-customer";

final http:Client testClient = check new (string `http://localhost:${servicePort}`);

# Builds a future expiration timestamp, `daysAhead` days from now.
#
# + daysAhead - number of days ahead of now the timestamp should be
# + return - the computed UTC timestamp
function futureExpiry(decimal daysAhead) returns time:Utc {
    return time:utcAddSeconds(time:utcNow(), daysAhead * 86400);
}

# Builds a past expiration timestamp, `daysAgo` days before now.
#
# + daysAgo - number of days before now the timestamp should be
# + return - the computed UTC timestamp
function pastExpiry(decimal daysAgo) returns time:Utc {
    return time:utcAddSeconds(time:utcNow(), -daysAgo * 86400);
}

# Stand-in for `fetchCustomerEntitlementsFromAws`, mocked in via `@test:Mock` below so the test
# suite never calls the real AWS Marketplace API. Routes each customer identifier to a canned
# response, or to a simulated AWS failure for `AWS_DOWN_CUSTOMER`.
#
# + customerIdentifier - the AWS Marketplace customer identifier to look up
# + return - the canned entitlements for the customer, or a simulated AWS error
function mockFetchCustomerEntitlementsFromAws(string customerIdentifier) returns mpe:Entitlement[]|error {
    if customerIdentifier == ENTITLED_CUSTOMER {
        return [
            {
                productCode,
                dimension: "Users",
                customerIdentifier: ENTITLED_CUSTOMER,
                expirationDate: futureExpiry(30),
                value: 10
            }
        ];
    }

    if customerIdentifier == OVER_ASKING_CUSTOMER {
        return [
            {
                productCode,
                dimension: "Users",
                customerIdentifier: OVER_ASKING_CUSTOMER,
                expirationDate: futureExpiry(30),
                value: 5
            }
        ];
    }

    if customerIdentifier == EXPIRED_CUSTOMER {
        return [
            {
                productCode,
                dimension: "Users",
                customerIdentifier: EXPIRED_CUSTOMER,
                expirationDate: pastExpiry(1),
                value: 10
            }
        ];
    }

    if customerIdentifier == UNKNOWN_CUSTOMER {
        return [];
    }

    if customerIdentifier == AWS_DOWN_CUSTOMER {
        return error mpe:Error("internal server error", httpStatusCode = 500,
                requestId = "aws-req-id-12345", errorCode = "InternalFailure");
    }

    return [];
}

@test:Mock {
    functionName: "fetchCustomerEntitlementsFromAws"
}
test:MockFunction mockFetchFunction = new ();

@test:BeforeSuite
function setupMockEntitlementFetch() {
    test:when(mockFetchFunction).call("mockFetchCustomerEntitlementsFromAws");
}

@test:Config {}
function testEntitledCustomerIsAllowed() returns error? {
    SeatCheckResult result = check testClient->/entitlements/customers/[ENTITLED_CUSTOMER]/seatCheck(
            dimension = "Users", amount = 5);
    test:assertTrue(result.allowed, msg = "expected entitled customer to be allowed");
    test:assertEquals(result.reason, "entitlement covers requested amount for dimension: Users",
            msg = "unexpected allow reason");
}

@test:Config {}
function testCustomerAskingForMoreThanHeldIsDenied() returns error? {
    SeatCheckResult result = check testClient->/entitlements/customers/[OVER_ASKING_CUSTOMER]/seatCheck(
            dimension = "Users", amount = 10);
    test:assertFalse(result.allowed, msg = "expected over-asking customer to be denied");
    test:assertEquals(result.reason, "requested amount exceeds entitled amount for dimension: Users",
            msg = "unexpected deny reason");
}

@test:Config {}
function testExpiredEntitlementIsTreatedAsNoEntitlement() returns error? {
    SeatCheckResult result = check testClient->/entitlements/customers/[EXPIRED_CUSTOMER]/seatCheck(
            dimension = "Users", amount = 1);
    test:assertFalse(result.allowed, msg = "expected customer with only an expired entitlement to be denied");
    test:assertEquals(result.reason, "no active entitlement held for dimension: Users",
            msg = "unexpected deny reason");
}

@test:Config {}
function testUnknownCustomerIsDenied() returns error? {
    SeatCheckResult result = check testClient->/entitlements/customers/[UNKNOWN_CUSTOMER]/seatCheck(
            dimension = "Users", amount = 1);
    test:assertFalse(result.allowed, msg = "expected unknown customer to be denied");
    test:assertEquals(result.reason, "no active entitlement held for dimension: Users",
            msg = "unexpected deny reason");
}

@test:Config {}
function testAwsFailureReturnsGenericBadGatewayWithoutSensitiveDetails() returns error? {
    http:Response response = check testClient->/entitlements/customers/[AWS_DOWN_CUSTOMER]/seatCheck(
            dimension = "Users", amount = 1);
    test:assertEquals(response.statusCode, 502, msg = "expected a bad gateway status when AWS fails");

    json responseBody = check response.getJsonPayload();
    string bodyText = responseBody.toJsonString();
    test:assertTrue(!bodyText.includes("aws-req-id-12345"), msg = "response must not leak the AWS request id");
    test:assertTrue(!bodyText.includes("InternalFailure"), msg = "response must not leak the raw AWS error code");
    test:assertTrue(!bodyText.includes(awsAccessKeyId), msg = "response must not leak AWS credentials");
    test:assertTrue(!bodyText.includes(awsSecretAccessKey), msg = "response must not leak AWS credentials");

    ErrorDetail errorDetail = check responseBody.cloneWithType(ErrorDetail);
    test:assertEquals(errorDetail.message, "failed to retrieve entitlements from AWS Marketplace",
            msg = "expected a generic upstream failure message");
}

@test:Config {}
function testBlankCustomerIdentifierIsRejectedBeforeCallingAws() returns error? {
    http:Response response = check testClient->/entitlements/customers/["%20"]/seatCheck(
            dimension = "Users", amount = 1);
    test:assertEquals(response.statusCode, 400, msg = "expected a bad request status for a blank identifier");

    json responseBody = check response.getJsonPayload();
    ErrorDetail errorDetail = check responseBody.cloneWithType(ErrorDetail);
    test:assertEquals(errorDetail.message, "customerIdentifier must not be blank",
            msg = "expected a blank-identifier validation message");
}

@test:Config {}
function testNegativeAmountIsRejectedAsBadRequest() returns error? {
    http:Response response = check testClient->/entitlements/customers/[ENTITLED_CUSTOMER]/seatCheck(
            dimension = "Users", amount = -1);
    test:assertEquals(response.statusCode, 400, msg = "expected a bad request status for a negative amount");

    json responseBody = check response.getJsonPayload();
    ErrorDetail errorDetail = check responseBody.cloneWithType(ErrorDetail);
    test:assertEquals(errorDetail.message, "amount must not be negative",
            msg = "expected a negative-amount validation message");
}
