// The two attribute names the Orders table is keyed and narrated on. These are the only hardcoded
// attribute names in the watcher - everything else is driven by what the change feed reports.
const string ORDER_ID_ATTRIBUTE = "OrderId";
const string STATUS_ATTRIBUTE = "Status";

// Statuses used by internal tests are marked with this prefix and are excluded from the running picture so
// they do not pollute the counts.
const string TEST_STATUS_PREFIX = "TEST_";

# The kind of change that happened to an order.
public enum OrderChangeKind {
    ORDER_PLACED,
    ORDER_STATUS_CHANGED,
    ORDER_REMOVED
}

# A narrated, ready-to-print change to a single order.
public type OrderChangeNarration record {|
    # The kind of change that happened
    OrderChangeKind kind;
    # Identifier of the order the change happened to
    string orderId;
    # Status the order had before the change, present for updates and removals when available
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
    # Number of order removals (REMOVE records) seen so far
    int removals;
    # For each shard currently being read, the identifier of the most recent change record handled from it -
    # so operations can see how far the watcher has got through the feed
    map<string> lastProcessedEventIdByShard;
|};
