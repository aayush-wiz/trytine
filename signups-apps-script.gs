// Tine — early-access signups → Google Sheet
// Paste this into Extensions → Apps Script of your Google Sheet, then Deploy as a Web app
// (Execute as: Me, Who has access: Anyone). It appends one row per signup: [timestamp, name, email].

function doPost(e) {
  try {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName('Signups') || ss.getSheets()[0];

    // first time: add a header row
    if (sheet.getLastRow() === 0) {
      sheet.appendRow(['Timestamp', 'Name', 'Email']);
    }

    var data = JSON.parse(e.postData.contents);
    sheet.appendRow([new Date(), data.name || '', data.email || '']);

    return ContentService
      .createTextOutput(JSON.stringify({ ok: true }))
      .setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService
      .createTextOutput(JSON.stringify({ ok: false, error: String(err) }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}
