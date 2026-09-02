import ballerina/test;

@test:Config {}
function testBuildReportObjectKey() {
    test:assertEquals(buildReportObjectKey("2026-09-01"), "2026-09-01.csv", msg = "Incorrect incoming object key");
}

@test:Config {}
function testBuildProcessedObjectKey() {
    test:assertEquals(buildProcessedObjectKey("2026-09-01"), "processed/2026-09-01.csv", msg = "Incorrect processed object key");
}

@test:Config {}
function testBuildArchiveObjectKey() {
    test:assertEquals(buildArchiveObjectKey("2026-09-01"), "archive/2026-09-01.csv", msg = "Incorrect archive object key");
}
