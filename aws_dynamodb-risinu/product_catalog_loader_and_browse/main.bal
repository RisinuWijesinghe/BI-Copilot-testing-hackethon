import ballerina/http;
import ballerina/log;

listener http:Listener catalogListener = new (servicePort);

service /catalog on catalogListener {

    // Loads a batch of products into the catalog in one go. Every product in the request is
    // validated first; if any one of them is invalid, nothing from the request is written and
    // a 400 names the offending product. Once validation passes, all products are written to
    // DynamoDB and the call only reports success once every single one is confirmed written —
    // it never reports success while some products silently failed to land.
    resource function post products(@http:Payload ProductBatchLoadRequest payload)
            returns ProductBatchLoadAccepted|http:BadRequest|http:BadGateway {
        RawProduct[] rawProducts = payload.products;

        Product[] validatedProducts = [];
        foreach RawProduct rawProduct in rawProducts {
            Product|InvalidProductDetail validationResult = validateProduct(rawProduct);
            if validationResult is InvalidProductDetail {
                return <http:BadRequest>{
                    body: {
                        message: "One or more products failed validation; nothing was written",
                        invalidProduct: validationResult
                    }
                };
            }
            validatedProducts.push(validationResult);
        }

        error? loadResult = loadProducts(validatedProducts);
        if loadResult is error {
            log:printError("Failed to load product batch into DynamoDB", loadResult,
                    tableName = catalogTableName, productCount = validatedProducts.length());
            return <http:BadGateway>{
                body: {message: "Unable to reach the catalog storage right now. Please try again later."}
            };
        }

        return <ProductBatchLoadAccepted>{loadedCount: validatedProducts.length()};
    }

    // Returns the requested products in one round trip. SKUs that don't exist are not an
    // error — they come back with found = false so the caller can tell exactly which of the
    // requested SKUs were present.
    resource function get products(string[] sku) returns ProductBatchLookupResponse|http:BadRequest|http:BadGateway {
        if sku.length() == 0 {
            return <http:BadRequest>{
                body: {message: "At least one sku must be provided"}
            };
        }

        ProductBatchLookupResponse|error lookupResult = lookupProducts(sku);
        if lookupResult is error {
            log:printError("Failed to look up products in DynamoDB", lookupResult,
                    tableName = catalogTableName, skuCount = sku.length());
            return <http:BadGateway>{
                body: {message: "Unable to reach the catalog storage right now. Please try again later."}
            };
        }

        return lookupResult;
    }

    // Returns the products in a category, cheapest first, optionally capped at a maximum price.
    // Only SKU, name and price come back — never the whole record.
    //
    // The catalog is far larger than any one response, so the caller works through the results a
    // page at a time: when more matches remain, `hasMore` is true and `nextCursor` carries the
    // position to resume from. A page is therefore never silently truncated, and the caller never
    // has to ask for everything at once.
    //
    // An unknown category is simply an empty page, not a 404 — the catalog holding nothing under
    // that name is an answer, not a failure.
    resource function get categories/[string category]/products(string? cursor, decimal? maxPrice,
            int 'limit = DEFAULT_PAGE_SIZE) returns CategoryProductPage|http:BadRequest|http:BadGateway {
        string trimmedCategory = category.trim();
        if trimmedCategory.length() == 0 {
            return <http:BadRequest>{
                body: {message: "A category must be provided"}
            };
        }
        if 'limit < 1 || 'limit > MAX_PAGE_SIZE {
            return <http:BadRequest>{
                body: {message: string `limit must be between 1 and ${MAX_PAGE_SIZE}`}
            };
        }

        CursorState? startAfter = ();
        if cursor is string {
            CursorState|error decoded = decodeCursor(cursor);
            if decoded is error {
                return <http:BadRequest>{
                    body: {message: "cursor is not a valid continuation token"}
                };
            }
            // A cursor is a position within one category's results; replaying it against another
            // category would resume from a meaningless place.
            if decoded.category != trimmedCategory {
                return <http:BadRequest>{
                    body: {message: "cursor belongs to a different category"}
                };
            }
            startAfter = decoded;
        }

        CategoryProductPage|error page = browseCategory(trimmedCategory, maxPrice, 'limit, startAfter);
        if page is error {
            log:printError("Failed to browse catalog category in DynamoDB", page,
                    tableName = catalogTableName, indexName = catalogCategoryIndexName,
                    category = trimmedCategory);
            return <http:BadGateway>{
                body: {message: "Unable to reach the catalog storage right now. Please try again later."}
            };
        }

        return page;
    }

    // Summarises the catalog: every category currently holding products, and roughly how many are
    // in each. The counts are approximate — the index backing them is eventually consistent — and
    // are tallied by streaming category names alone, so no product is ever pulled into memory.
    resource function get categories() returns CategorySummaryResponse|http:BadGateway {
        CategorySummaryResponse|error summary = summarizeCategories();
        if summary is error {
            log:printError("Failed to summarise catalog categories in DynamoDB", summary,
                    tableName = catalogTableName, indexName = catalogCategoryIndexName);
            return <http:BadGateway>{
                body: {message: "Unable to reach the catalog storage right now. Please try again later."}
            };
        }

        return summary;
    }
}
