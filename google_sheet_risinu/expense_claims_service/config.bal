// Google Sheets location where expense claims for the current month are recorded.
configurable string spreadsheetId = ?;
configurable string sheetName = ?;

// Tab used to hold the month-end snapshot of category totals.
configurable string snapshotSheetName = ?;

// Google OAuth2 credentials used to authenticate with the Google Sheets API.
configurable string clientId = ?;
configurable string clientSecret = ?;
configurable string refreshToken = ?;
configurable string refreshUrl = "https://oauth2.googleapis.com/token";
