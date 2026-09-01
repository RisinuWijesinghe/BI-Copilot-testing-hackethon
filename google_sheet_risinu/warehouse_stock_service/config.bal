// Google Sheets location where warehouse stock is recorded. Each row is a SKU with a product
// name, the quantity on hand and a reorder threshold.
configurable string spreadsheetId = ?;
configurable string sheetName = ?;

// Google OAuth2 credentials used to authenticate with the Google Sheets API.
configurable string clientId = ?;
configurable string clientSecret = ?;
configurable string refreshToken = ?;
configurable string refreshUrl = "https://oauth2.googleapis.com/token";
