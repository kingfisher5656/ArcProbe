function uploadSheetID() { 
  var sheet = CURRENT_SPREADSHEET.getActiveSheet();
  var sheetName = sheet.getName();
  if (sheetName !== TAB_NAME_DICTIONARY.MAIN) return;

  const ui = SpreadsheetApp.getUi();
  const uploadMsg1 = CURRENT_SPREADSHEET.getRangeByName('MenuTranslation!I2').getValue();
  const response = ui.alert(
      uploadMsg1, ui.ButtonSet.OK_CANCEL,
  );
  if (response !== ui.Button.OK) {
    return;
  }

  var username = sheet.getRange("H12").getValue();
  var sheetID = sheet.getRange("H13").getValue();
  if (!username) {
    const errMsg1 = CURRENT_SPREADSHEET.getRangeByName('MenuTranslation!I3').getValue();
    Browser.msgBox(errMsg1);
    return;
  }
  if (!sheetID) {
    const errMsg2 = CURRENT_SPREADSHEET.getRangeByName('MenuTranslation!I4').getValue();
    Browser.msgBox(errMsg2);
    return;
  }

  var file = DriveApp.getFileById(CURRENT_SPREADSHEET.getId());
  var permissions = file.getSharingAccess();

  // 현재 권한이 제한된 경우에 변경
  if (permissions === DriveApp.Access.PRIVATE) {
    file.setSharing(DriveApp.Access.ANYONE, DriveApp.Permission.VIEW);
  }

  var originalSheet = SpreadsheetApp.openById("1m0ktV0jv-NJ6LzX9Ldjhpl2gzz0tuW28O9rYdUMltlY").getSheetByName("database_v9.0.0");
  var data = originalSheet.getRange("A:A").getValues().flat();

  if (data.includes(sheetID)) {
    const errMsg3 = CURRENT_SPREADSHEET.getRangeByName('MenuTranslation!I5').getValue();
    Browser.msgBox(errMsg3);
    return;
  }

  var lastRow = originalSheet.getLastRow();
  var nextRow = lastRow + 1;
  originalSheet.getRange(nextRow, 1).setValue(sheetID);

  const uploadMsg2 = CURRENT_SPREADSHEET.getRangeByName('MenuTranslation!I6').getValue();
  Browser.msgBox(uploadMsg2);
}
