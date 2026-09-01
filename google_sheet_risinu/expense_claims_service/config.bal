// Google Sheets location where expense claims for the current month are recorded.
configurable string spreadsheetId = ?;
configurable string sheetName = ?;

// Google OAuth2 credentials used to authenticate with the Google Sheets API.
configurable string clientId = ?;
configurable string clientSecret = ?;
configurable string refreshToken = ?;
configurable string refreshUrl = "https://oauth2.googleapis.com/token";
