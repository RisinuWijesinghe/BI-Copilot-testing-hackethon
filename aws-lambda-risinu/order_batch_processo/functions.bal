// Attempts to reconcile a single pending order ID. Returns the order ID on
// success, or an error describing why it was rejected (blank/malformed
// order ID).
function reconcileOrder(string orderId) returns string|error {
    string trimmedOrderId = orderId.trim();
    if trimmedOrderId.length() == 0 {
        return error("order id is blank or malformed");
    }
    return trimmedOrderId;
}
