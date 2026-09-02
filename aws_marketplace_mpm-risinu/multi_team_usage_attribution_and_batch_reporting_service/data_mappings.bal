import ballerina/time;
import ballerinax/aws.marketplace.mpm;

# Maps a single team usage event into an AWS Marketplace usage record, tagging the full quantity
# with the internal team it came from so it can later be reconciled against internal cost reports.
#
# + teamUsageEvent - The usage event collected from an internal team
# + return - The AWS Marketplace usage record to submit, or an error if the timestamp is invalid
function mapToUsageRecord(TeamUsageEvent teamUsageEvent) returns mpm:UsageRecord|error {
    time:Utc usageUtcTimestamp = check time:utcFromString(teamUsageEvent.usageTimestamp);

    mpm:Tag internalTeamTag = {
        'key: "internalTeam",
        value: teamUsageEvent.internalTeam
    };

    mpm:UsageAllocation usageAllocation = {
        allocatedUsageQuantity: teamUsageEvent.quantity,
        tags: [internalTeamTag]
    };

    return {
        customerAWSAccountId: teamUsageEvent.customerAwsAccountId,
        dimension: teamUsageEvent.dimension,
        quantity: teamUsageEvent.quantity,
        timestamp: usageUtcTimestamp,
        usageAllocations: [usageAllocation]
    };
}

