import ballerina/test;

@test:Config {}
function testValidateClaimRejectsMissingDate() {
    ExpenseClaim claim = {date: "", category: "Travel", description: "Taxi", amount: 10.50d};
    ValidationErrorDetail? validationError = validateClaim(claim);
    test:assertTrue(validationError is ValidationErrorDetail, msg = "expected a validation error for missing date");
    ValidationErrorDetail errorDetail = <ValidationErrorDetail>validationError;
    test:assertEquals(errorDetail.message, "date is required", msg = "unexpected message for missing date");
}

@test:Config {}
function testValidateClaimRejectsMissingCategory() {
    ExpenseClaim claim = {date: "2026-09-01", category: "", description: "Taxi", amount: 10.50d};
    ValidationErrorDetail? validationError = validateClaim(claim);
    test:assertTrue(validationError is ValidationErrorDetail, msg = "expected a validation error for missing category");
    ValidationErrorDetail errorDetail = <ValidationErrorDetail>validationError;
    test:assertEquals(errorDetail.message, "category is required", msg = "unexpected message for missing category");
}

@test:Config {}
function testValidateClaimRejectsMissingDescription() {
    ExpenseClaim claim = {date: "2026-09-01", category: "Travel", description: "", amount: 10.50d};
    ValidationErrorDetail? validationError = validateClaim(claim);
    test:assertTrue(validationError is ValidationErrorDetail, msg = "expected a validation error for missing description");
    ValidationErrorDetail errorDetail = <ValidationErrorDetail>validationError;
    test:assertEquals(errorDetail.message, "description is required", msg = "unexpected message for missing description");
}

@test:Config {}
function testValidateClaimRejectsNonPositiveAmount() {
    ExpenseClaim claim = {date: "2026-09-01", category: "Travel", description: "Taxi", amount: 0d};
    ValidationErrorDetail? validationError = validateClaim(claim);
    test:assertTrue(validationError is ValidationErrorDetail, msg = "expected a validation error for a zero amount");
    ValidationErrorDetail errorDetail = <ValidationErrorDetail>validationError;
    test:assertEquals(errorDetail.message, "amount must be a positive number", msg = "unexpected message for a zero amount");
}

@test:Config {}
function testValidateClaimRejectsNegativeAmount() {
    ExpenseClaim claim = {date: "2026-09-01", category: "Travel", description: "Taxi", amount: -5d};
    ValidationErrorDetail? validationError = validateClaim(claim);
    test:assertTrue(validationError is ValidationErrorDetail, msg = "expected a validation error for a negative amount");
    ValidationErrorDetail errorDetail = <ValidationErrorDetail>validationError;
    test:assertEquals(errorDetail.message, "amount must be a positive number", msg = "unexpected message for a negative amount");
}

@test:Config {}
function testValidateClaimRejectsUnknownCategory() {
    ExpenseClaim claim = {date: "2026-09-01", category: "Entertainment", description: "Concert", amount: 25d};
    ValidationErrorDetail? validationError = validateClaim(claim);
    test:assertTrue(validationError is ValidationErrorDetail, msg = "expected a validation error for an unknown category");
    ValidationErrorDetail errorDetail = <ValidationErrorDetail>validationError;
    test:assertEquals(errorDetail.message, "category must be one of: Travel, Meals, Office, Other",
            msg = "unexpected message for an unknown category");
}

@test:Config {}
function testValidateClaimAcceptsValidClaim() {
    ExpenseClaim claim = {date: "2026-09-01", category: "Travel", description: "Taxi", amount: 10.50d};
    ValidationErrorDetail? validationError = validateClaim(claim);
    test:assertTrue(validationError is (), msg = "expected no validation error for a valid claim");
}

@test:Config {}
function testValidateCategoryRejectsUnknownCategory() {
    ValidationErrorDetail? validationError = validateCategory("Entertainment");
    test:assertTrue(validationError is ValidationErrorDetail, msg = "expected a validation error for an unknown category");
    ValidationErrorDetail errorDetail = <ValidationErrorDetail>validationError;
    test:assertEquals(errorDetail.message, "category must be one of: Travel, Meals, Office, Other",
            msg = "unexpected message for an unknown category");
}

@test:Config {}
function testValidateCategoryAcceptsKnownCategory() {
    ValidationErrorDetail? validationError = validateCategory("Meals");
    test:assertTrue(validationError is (), msg = "expected no validation error for a known category");
}

@test:Config {}
function testAggregateClaimsSummarySkipsUnparseableRows() {
    (int|string|decimal)[][] rowsValues = [
        ["2026-09-01", "Travel", "Taxi", 100d],
        ["2026-09-02", "Meals", "Lunch", 20d],
        ["2026-09-03", "Travel", "not-a-number", "abc"],
        ["2026-09-04", "Office", "", ""],
        ["2026-09-05", "Meals", "Dinner", 30d]
    ];

    ClaimsSummary summary = aggregateClaimsSummary(rowsValues);

    test:assertEquals(summary.totalsByCategory.get("Travel"), 100d, msg = "unexpected Travel total");
    test:assertEquals(summary.totalsByCategory.get("Meals"), 50d, msg = "unexpected Meals total");
    test:assertEquals(summary.totalsByCategory.get("Office"), 0d, msg = "unclaimed Office category should read as zero");
    test:assertEquals(summary.totalsByCategory.get("Other"), 0d, msg = "unclaimed Other category should read as zero");
    test:assertEquals(summary.overallTotal, 150d, msg = "unexpected overall total");
    test:assertEquals(summary.skippedRowCount, 2, msg = "unexpected skipped row count");
}

@test:Config {}
function testAggregateClaimsSummaryHandlesStringAmounts() {
    (int|string|decimal)[][] rowsValues = [
        ["2026-09-01", "Travel", "Taxi", "100.50"],
        ["2026-09-02", "Office", "Stationery", "49.50"]
    ];

    ClaimsSummary summary = aggregateClaimsSummary(rowsValues);

    test:assertEquals(summary.totalsByCategory.get("Travel"), 100.50d, msg = "unexpected Travel total for string amount");
    test:assertEquals(summary.totalsByCategory.get("Office"), 49.50d, msg = "unexpected Office total for string amount");
    test:assertEquals(summary.overallTotal, 150d, msg = "unexpected overall total for string amounts");
    test:assertEquals(summary.skippedRowCount, 0, msg = "no rows should have been skipped");
}

@test:Config {}
function testAggregateClaimsSummaryOnEmptySheetReturnsZeros() {
    (int|string|decimal)[][] rowsValues = [];

    ClaimsSummary summary = aggregateClaimsSummary(rowsValues);

    test:assertEquals(summary.totalsByCategory.get("Travel"), 0d, msg = "expected zero for Travel on an empty sheet");
    test:assertEquals(summary.totalsByCategory.get("Meals"), 0d, msg = "expected zero for Meals on an empty sheet");
    test:assertEquals(summary.totalsByCategory.get("Office"), 0d, msg = "expected zero for Office on an empty sheet");
    test:assertEquals(summary.totalsByCategory.get("Other"), 0d, msg = "expected zero for Other on an empty sheet");
    test:assertEquals(summary.overallTotal, 0d, msg = "expected zero overall total on an empty sheet");
    test:assertEquals(summary.skippedRowCount, 0, msg = "expected no skipped rows on an empty sheet");
}

@test:Config {}
function testAggregateCategorySummarySkipsUnparseableRows() {
    (int|string|decimal)[][] rowsValues = [
        ["2026-09-01", "Meals", "Lunch", 20d],
        ["2026-09-02", "Meals", "bad-amount", "xyz"],
        ["2026-09-03", "Meals", "Dinner", 30d],
        ["2026-09-04", "Travel", "Taxi", 100d]
    ];

    CategorySummary summary = aggregateCategorySummary(rowsValues, "Meals");

    test:assertEquals(summary.category, "Meals", msg = "unexpected category in summary");
    test:assertEquals(summary.total, 50d, msg = "unexpected total for Meals");
    test:assertEquals(summary.skippedRowCount, 1, msg = "unexpected skipped row count for Meals");
}

@test:Config {}
function testBuildSnapshotLinesIncludesGrandTotal() {
    ClaimsSummary summary = {
        totalsByCategory: {"Travel": 100d, "Meals": 50d, "Office": 0d, "Other": 0d},
        overallTotal: 150d,
        skippedRowCount: 0
    };

    SnapshotLine[] lines = buildSnapshotLines(summary);

    test:assertEquals(lines.length(), 5, msg = "expected 4 category lines plus a grand total line");
    test:assertEquals(lines[0], {label: "Travel", total: 100d}, msg = "unexpected first line");
    test:assertEquals(lines[1], {label: "Meals", total: 50d}, msg = "unexpected second line");
    test:assertEquals(lines[2], {label: "Office", total: 0d}, msg = "unexpected third line");
    test:assertEquals(lines[3], {label: "Other", total: 0d}, msg = "unexpected fourth line");
    test:assertEquals(lines[4], {label: "Grand Total", total: 150d}, msg = "unexpected grand total line");
}
