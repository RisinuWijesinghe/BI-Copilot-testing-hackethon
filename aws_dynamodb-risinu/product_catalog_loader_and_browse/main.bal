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
}
