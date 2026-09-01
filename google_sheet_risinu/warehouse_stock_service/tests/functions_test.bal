import ballerina/test;

@test:Config {}
function testValidateSkuRejectsBlank() {
    ValidationErrorDetail? validationError = validateSku("   ");
    test:assertTrue(validationError is ValidationErrorDetail, msg = "expected a validation error for a blank sku");
    ValidationErrorDetail errorDetail = <ValidationErrorDetail>validationError;
    test:assertEquals(errorDetail.message, "sku is required", msg = "unexpected message for a blank sku");
}

@test:Config {}
function testValidateSkuRejectsMalformedSku() {
    ValidationErrorDetail? validationError = validateSku("SKU 123!");
    test:assertTrue(validationError is ValidationErrorDetail, msg = "expected a validation error for a malformed sku");
    ValidationErrorDetail errorDetail = <ValidationErrorDetail>validationError;
    test:assertEquals(errorDetail.message, "sku is malformed: only letters, digits, hyphens and underscores are allowed",
            msg = "unexpected message for a malformed sku");
}

@test:Config {}
function testValidateSkuAcceptsWellFormedSku() {
    ValidationErrorDetail? validationError = validateSku("SKU-123_A");
    test:assertTrue(validationError is (), msg = "expected no validation error for a well-formed sku");
}

@test:Config {}
function testValidateMovementQuantityRejectsZero() {
    ValidationErrorDetail? validationError = validateMovementQuantity(0d);
    test:assertTrue(validationError is ValidationErrorDetail, msg = "expected a validation error for a zero movement");
    ValidationErrorDetail errorDetail = <ValidationErrorDetail>validationError;
    test:assertEquals(errorDetail.message, "quantityChange must not be zero", msg = "unexpected message for a zero movement");
}

@test:Config {}
function testValidateMovementQuantityAcceptsPositive() {
    ValidationErrorDetail? validationError = validateMovementQuantity(10d);
    test:assertTrue(validationError is (), msg = "expected no validation error for a positive movement");
}

@test:Config {}
function testValidateMovementQuantityAcceptsNegative() {
    ValidationErrorDetail? validationError = validateMovementQuantity(-5d);
    test:assertTrue(validationError is (), msg = "expected no validation error for a negative movement");
}

@test:Config {}
function testLocateStockRowFindsRowCaseInsensitively() {
    (int|string|decimal)[][] rowsValues = [
        ["sku-1", "Widget", 10d, 5d],
        ["SKU-2", "Gadget", 2d, 3d]
    ];

    LocatedStockRow? locatedRow = locateStockRow(rowsValues, "sku-2", 1);
    test:assertTrue(locatedRow is LocatedStockRow, msg = "expected to find sku-2 case-insensitively");
    LocatedStockRow row = <LocatedStockRow>locatedRow;
    test:assertEquals(row.sku, "SKU-2", msg = "unexpected sku casing in located row");
    test:assertEquals(row.rowPosition, 3, msg = "unexpected absolute row position");
}

@test:Config {}
function testLocateStockRowReturnsNilWhenNotFound() {
    (int|string|decimal)[][] rowsValues = [
        ["SKU-1", "Widget", 10d, 5d]
    ];

    LocatedStockRow? locatedRow = locateStockRow(rowsValues, "SKU-999", 1);
    test:assertTrue(locatedRow is (), msg = "expected no row to be located for an unknown sku");
}

@test:Config {}
function testMapToStockLevelFlagsLowStock() {
    LocatedStockRow locatedRow = {sku: "SKU-1", productName: "Widget", quantityOnHand: 3d, reorderThreshold: 5d, rowPosition: 2};
    StockLevel stockLevel = mapToStockLevel(locatedRow);
    test:assertTrue(stockLevel.lowStock, msg = "expected low stock to be flagged when quantity is below threshold");
}

@test:Config {}
function testMapToStockLevelDoesNotFlagHealthyStock() {
    LocatedStockRow locatedRow = {sku: "SKU-1", productName: "Widget", quantityOnHand: 20d, reorderThreshold: 5d, rowPosition: 2};
    StockLevel stockLevel = mapToStockLevel(locatedRow);
    test:assertFalse(stockLevel.lowStock, msg = "did not expect low stock to be flagged when quantity is above threshold");
}

@test:Config {}
function testFindDuplicateSkusDetectsCaseInsensitiveDuplicates() {
    SkuMovement[] movements = [
        {sku: "SKU-1", quantityChange: 5d},
        {sku: "SKU-2", quantityChange: 3d},
        {sku: "sku-1", quantityChange: -1d}
    ];

    string[] duplicates = findDuplicateSkus(movements);
    test:assertEquals(duplicates.length(), 1, msg = "expected exactly one duplicated sku");
    test:assertEquals(duplicates[0], "sku-1", msg = "expected the second occurrence's casing to be reported");
}

@test:Config {}
function testFindDuplicateSkusReturnsEmptyWhenAllUnique() {
    SkuMovement[] movements = [
        {sku: "SKU-1", quantityChange: 5d},
        {sku: "SKU-2", quantityChange: 3d}
    ];

    string[] duplicates = findDuplicateSkus(movements);
    test:assertEquals(duplicates.length(), 0, msg = "expected no duplicates when all skus are unique");
}

@test:Config {}
function testValidateRetireEligibilityRejectsRemainingStock() {
    LocatedStockRow locatedRow = {sku: "SKU-1", productName: "Widget", quantityOnHand: 4d, reorderThreshold: 5d, rowPosition: 2};
    StockRemainingDetail? validationError = validateRetireEligibility(locatedRow);
    test:assertTrue(validationError is StockRemainingDetail, msg = "expected retirement to be rejected while stock remains");
    StockRemainingDetail errorDetail = <StockRemainingDetail>validationError;
    test:assertEquals(errorDetail.quantityOnHand, 4d, msg = "unexpected remaining quantity in rejection detail");
}

@test:Config {}
function testValidateRetireEligibilityAcceptsZeroStock() {
    LocatedStockRow locatedRow = {sku: "SKU-1", productName: "Widget", quantityOnHand: 0d, reorderThreshold: 5d, rowPosition: 2};
    StockRemainingDetail? validationError = validateRetireEligibility(locatedRow);
    test:assertTrue(validationError is (), msg = "expected retirement to be allowed when no stock remains");
}

