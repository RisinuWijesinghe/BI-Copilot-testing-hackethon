// The two attribute names the Orders table is keyed and narrated on. These are the only hardcoded
// attribute names in the watcher - everything else is driven by what the change feed reports.
const string ORDER_ID_ATTRIBUTE = "OrderId";
const string STATUS_ATTRIBUTE = "Status";

// Marks the identity DynamoDB itself uses when its Time to Live process expires an item, as opposed to
// a manual delete performed by a person or application.
const string TTL_PRINCIPAL_ID = "dynamodb.amazonaws.com";
const string TTL_IDENTITY_TYPE = "Service";

// Statuses used by internal tests are marked with this prefix and are excluded from the running picture so
// they do not pollute the counts.
const string TEST_STATUS_PREFIX = "TEST_";

# The kind of change that happened to an order.
public enum OrderChangeKind {
    ORDER_PLACED,
    ORDER_STATUS_CHANGED,
    ORDER_EXPIRED,
    ORDER_DELETED
}

# A narrated, ready-to-print change to a single order.
public type OrderChangeNarration record {|
    # The kind of change that happened
    OrderChangeKind kind;
    # Identifier of the order the change happened to
    string orderId;
    # Status the order had before the change, present for updates and deletions when available
    string previousStatus?;
    # Status the order has after the change, present for new orders and updates
    string newStatus?;
|};

# The running picture of what the watcher has seen so far, exposed over the stats endpoint.
public type WatcherStats record {|
    # Number of orders placed (INSERT records) seen so far
    int placements;
    # Number of order status updates (MODIFY records) seen so far
    int updates;
    # Number of order removals (REMOVE records, whether expired or deleted) seen so far
    int removals;
    # Number of orders currently sitting in each status, keyed by status value
    map<int> ordersByStatus;
    # When the last change came through, as an RFC 3339 timestamp, absent if nothing has been seen yet
    string lastChangeAt?;
|};
