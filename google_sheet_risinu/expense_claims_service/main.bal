import ballerina/http;
import ballerinax/googleapis.sheets;

service /claims on new http:Listener(8080) {

    # Records a new expense claim as a row in the current month's Google Sheet.
    #
    # + claim - the expense claim submitted by the caller
    # + return - a confirmation with the row the claim landed in, a validation error, or a generic failure message
    resource function post .(@http:Payload ExpenseClaim claim) returns ClaimConfirmation|http:BadRequest|http:InternalServerError {
        ValidationErrorDetail? validationError = validateClaim(claim);
        if validationError is ValidationErrorDetail {
            return <http:BadRequest>{
                body: {message: validationError.message}
            };
        }

        (int|string|decimal|boolean|float)[] rowValues = mapClaimToRowValues(claim);
        sheets:A1Range targetRange = buildTargetRange();

        sheets:ValueRange|error appendResult = sheetsClient->appendValue(spreadsheetId, rowValues, targetRange);
        if appendResult is error {
            return <http:InternalServerError>{
                body: {message: "could not record the claim, please retry"}
            };
        }

        return {
            message: "claim recorded",
            rowNumber: appendResult.rowPosition
        };
    }
}
