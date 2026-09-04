// AWS region the DynamoDB table lives in.
configurable string awsRegion = ?;

// DynamoDB table holding the product catalog. Provisioned externally; this service only reads and writes it.
configurable string catalogTableName = ?;

// HTTP listener port.
configurable int servicePort = 8080;

// Global secondary index used to browse the catalog by category, and to summarise it without
// reading whole products. Provisioned externally alongside the table, with Category as the
// partition key, Price as the sort key, and Name projected into it so a category listing can be
// served entirely from the index. Only the name is configured here; the service never creates
// or alters it.
configurable string catalogCategoryIndexName = "Category-Price-index";

// Number of products returned by a category listing when the caller doesn't ask for a size,
// and the ceiling it may ask for.
const int DEFAULT_PAGE_SIZE = 50;
const int MAX_PAGE_SIZE = 200;
