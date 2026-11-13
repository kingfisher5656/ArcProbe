function autoScoreInputButton() {
  const arcaeaOnlineSheet = getTabWithId(TAB_NAME_DICTIONARY.ARCAEA_ONLINE);
  const scoreInputSheet = getTabWithId(TAB_NAME_DICTIONARY.SCORE_INPUT);

  // 입력 가능한 점수가 입력되었을 때만 작동
  if (arcaeaOnlineSheet.getRange("K75").getValue() !== 0) {
    const inputMsg2 = CURRENT_SPREADSHEET.getRangeByName('MenuTranslation!I7').getValue();
    Browser.msgBox(inputMsg2);
    return;
  }

  var songInput = arcaeaOnlineSheet.getRange("G76:G125").getValues().flat().map(String);
  var scoreInput = arcaeaOnlineSheet.getRange("I76:I125").getValues().flat();
  var songDB = scoreInputSheet.getRange("B:B").getValues().flat().map(String);
  console.log("test")

  songInput.forEach((song, index) => {
    if (song) {
      var rowIndex = songDB.indexOf(song);
      if (rowIndex !== -1) {
        scoreInputSheet.getRange(rowIndex + 1, 8).setValue(scoreInput[index]);
      }
    }
  });

  var now = new Date();
  arcaeaOnlineSheet.getRange("I21").setValue(Utilities.formatDate(now, Session.getScriptTimeZone(), "yyyy/MM/dd HH:mm"));
  // resetCellStyles(arcaeaOnlineSheet);
}

function resetCellStyles(sheet) {
  var rangeWhite = sheet.getRange("F8:F");
  var rangeDoubleStroke = sheet.getRange("F1:F");
  var rangeBox = sheet.getRange("G8:G22");
  var rangeMiniBox = sheet.getRangeList(["G25:G74", "G76:G125"]);
  var rangeBlue = sheet.getRange("F7");

  rangeWhite.setBackground("#FFFFFF").setFontColor("#FFFFFF").setFontSize(1).setWrapStrategy(SpreadsheetApp.WrapStrategy.WRAP);;
  rangeBlue.setBackground("#deeaf6").setFontColor("#deeaf6").setFontSize(1).setWrapStrategy(SpreadsheetApp.WrapStrategy.WRAP);;

  rangeDoubleStroke.setBorder(false, true, false, false, false, false, "#000000", SpreadsheetApp.BorderStyle.DOUBLE);
  rangeBox.setBorder(null, true, null, null, null, null, "#666666", SpreadsheetApp.BorderStyle.SOLID_MEDIUM);
  rangeMiniBox.setBorder(null, true, null, null, null, null, "#666666", SpreadsheetApp.BorderStyle.SOLID);
}