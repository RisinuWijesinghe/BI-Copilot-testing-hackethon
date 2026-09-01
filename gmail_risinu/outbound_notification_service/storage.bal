// In-memory store of notifications, keyed by notification identifier. Holds both
// parked (unsent) notifications awaiting review and notifications that have already
// been sent, so that approving an already-sent or unknown identifier can be told apart.
final map<StoredNotification> notificationStore = {};

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
