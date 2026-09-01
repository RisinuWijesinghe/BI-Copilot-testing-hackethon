// In-memory store of notifications, keyed by notification identifier. Holds both
// parked (unsent) notifications awaiting review and notifications that have already
// been sent, so that approving an already-sent or unknown identifier can be told apart.
final map<StoredNotification> notificationStore = {};

// Running counters since startup. Sent and discarded counts are cumulative and are
// not decremented, so history is preserved even though the store only holds current
// parked/sent entries (a discard removes the entry from notificationStore entirely).
int sentCount = 0;
int discardedCount = 0;

function storeNotification(StoredNotification notification) {
    notificationStore[notification.notificationId] = notification;
}

function getNotification(string notificationId) returns StoredNotification? {
    return notificationStore[notificationId];
}

function listParkedNotifications() returns StoredNotification[] {
    return from StoredNotification notification in notificationStore
        where notification.status == "PARKED"
        select notification;
}

// Removes a notification from the store entirely, e.g. once discarded.
function removeNotification(string notificationId) {
    _ = notificationStore.removeIfHasKey(notificationId);
}

function markSent() {
    sentCount += 1;
}

function markDiscarded() {
    discardedCount += 1;
}

function currentStats() returns NotificationStats {
    int parkedCount = listParkedNotifications().length();
    return {
        parkedCount,
        sentCount,
        discardedCount
    };
}
