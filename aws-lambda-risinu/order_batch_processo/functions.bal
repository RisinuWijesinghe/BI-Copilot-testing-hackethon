// Attempts to parse and validate a single SQS message body as an order.
// Returns the parsed OrderRecord on success, or an error describing why the
// message was rejected (invalid JSON or missing required fields).
function parseOrder(string messageBody) returns OrderRecord|error {
    json orderJson = check messageBody.fromJsonString();
    OrderRecord|error orderRecord = orderJson.cloneWithType();
    if orderRecord is error {
        return error("order message missing required fields", orderRecord);
    }
    return orderRecord;
}
