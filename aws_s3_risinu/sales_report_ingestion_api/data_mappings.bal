import ballerina/data.csv;

# Parses the raw CSV content of a sales report into an array of rows.
#
# + csvContent - the raw CSV text content
# + return - the parsed report rows, or an error if the content is not valid CSV
function parseReportCsv(string csvContent) returns SalesReportRow[]|error => csv:parseString(csvContent);

# Validates and converts a raw CSV row into a `ValidSalesRow`.
# Rows with a missing or unparseable revenue value are dropped by returning `()`.
#
# + rawRow - the raw CSV row, with all values as strings
# + return - the validated row, or `()` if the row's revenue is missing or unparseable
function toValidSalesRow(SalesReportRow rawRow) returns ValidSalesRow? {
    string? product = rawRow["product"];
    string? revenueText = rawRow["revenue"];
    if product is () || revenueText is () {
        return ();
    }

    decimal|error revenue = decimal:fromString(revenueText);
    if revenue is error {
        return ();
    }

    return {product, revenue};
}

# Aggregates a set of validated sales rows into a daily report summary.
#
# + reportDate - the report date
# + validRows - the validated sales rows
# + skippedRowCount - the number of rows dropped due to missing or unparseable values
# + return - the aggregated report summary
function summarizeValidRows(string reportDate, ValidSalesRow[] validRows, int skippedRowCount) returns ReportSummaryResponse {
    decimal totalRevenue = 0d;
    map<decimal> revenueByProduct = {};
    foreach ValidSalesRow validRow in validRows {
        totalRevenue += validRow.revenue;
        decimal existingRevenue = revenueByProduct[validRow.product] ?: 0d;
        revenueByProduct[validRow.product] = existingRevenue + validRow.revenue;
    }

    return {
        date: reportDate,
        rowCount: validRows.length(),
        totalRevenue,
        bestSellingProduct: findBestSellingProduct(revenueByProduct),
        skippedRowCount
    };
}

# Finds the product with the highest aggregated revenue.
#
# + revenueByProduct - a map of product name to aggregated revenue
# + return - the best-selling product name, or an empty string if there are no products
function findBestSellingProduct(map<decimal> revenueByProduct) returns string {
    string bestSellingProduct = "";
    decimal highestRevenue = -1d;
    foreach [string, decimal] [product, revenue] in revenueByProduct.entries() {
        if revenue > highestRevenue {
            highestRevenue = revenue;
            bestSellingProduct = product;
        }
    }
    return bestSellingProduct;
}
