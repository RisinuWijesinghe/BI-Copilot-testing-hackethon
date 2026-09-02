import ballerina/time;
import ballerinax/aws.marketplace.mpe;

# Converts an entitlement's raw value into a decimal amount. Non-numeric values (e.g. boolean
# flags) are treated as a unit amount of one.
#
# + entitlementValue - the raw entitlement value returned by AWS Marketplace
# + return - the numeric amount to expose to the caller
function toAmount(boolean|float|int|string? entitlementValue) returns decimal {
    if entitlementValue is int {
        return <decimal>entitlementValue;
    }
    if entitlementValue is float {
        return <decimal>entitlementValue;
    }
    if entitlementValue is string {
        decimal|error parsed = decimal:fromString(entitlementValue);
        if parsed is decimal {
            return parsed;
        }
        return 1d;
    }
    return 1d;
}

# Maps a single AWS Marketplace entitlement to the public entitlement info shape.
#
# + entitlement - the AWS Marketplace entitlement to convert
# + return - the entitlement info exposed to callers
function toEntitlementInfo(mpe:Entitlement entitlement) returns EntitlementInfo => {
    dimension: entitlement?.dimension ?: "",
    amount: toAmount(entitlement?.value),
    expiryDate: mapExpiryDate(entitlement?.expirationDate)
};

# Converts an optional AWS expiration timestamp into an RFC 3339 string, if present.
#
# + expirationDate - the raw AWS expiration timestamp
# + return - the RFC 3339 timestamp, or `()` if the entitlement has no expiry
function mapExpiryDate(time:Utc? expirationDate) returns string? {
    if expirationDate is () {
        return ();
    }
    return time:utcToString(expirationDate);
}

# Maps a full list of AWS Marketplace entitlements to the public entitlement info shape.
#
# + entitlements - the AWS Marketplace entitlements to convert
# + return - the entitlement infos exposed to callers
function toEntitlementInfoList(mpe:Entitlement[] entitlements) returns EntitlementInfo[] =>
    from mpe:Entitlement entitlement in entitlements
    select toEntitlementInfo(entitlement);
