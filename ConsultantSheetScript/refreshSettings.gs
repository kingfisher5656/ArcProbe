function getSheetId() {
  const sheetIdCell = getTabWithId(TAB_NAME_DICTIONARY.MAIN).getRange("H13");
  const sheetIdValue = CURRENT_SPREADSHEET.getId();
  sheetIdCell.setValue(sheetIdValue);
}

const latestVersionCells = [
  { cell: getTabWithId(TAB_NAME_DICTIONARY.MAIN).getRange("C22"), 
    formula: `=LET(
  sourceSheetName, "1aUhG8C-0wVsL_jMPwpkZ4hXMH5zN9sZDM_wGBb4On0w",
  latestVersion, IMPORTRANGE(sourceSheetName,"DevSettings!C4"),
  isUnderMaintenance, IMPORTRANGE(sourceSheetName,"DevSettings!F21"),
  loadingText, SWITCH(
      DevSettings!$C$21,
      "한국어", "↻ 로드 중...",
      "English", "↻ Loading...",
      "日本語", "↻ ロード中..."
  ),
  SWITCH(
    IFERROR(ERROR.TYPE(isUnderMaintenance), 0),
    4, loadingText,
    10, loadingText,
    0, 
    IF(
      isUnderMaintenance,
      DevSettings!$K$3,
      latestVersion
    ),
    SWITCH(
      DevSettings!$C$21,
      "한국어", "✘ 오류 코드: ",
      "English", "✘ Error Code: ",
      "日本語", "✘ エラーコード: "
    )&IFERROR(ERROR.TYPE(isUnderMaintenance), 0)
  )
)`}, 
  { cell: getTabWithId(TAB_NAME_DICTIONARY.MAIN).getRange("E22"),
    formula: `=LET(
  sourceSheetName, "1aUhG8C-0wVsL_jMPwpkZ4hXMH5zN9sZDM_wGBb4On0w",
  latestVersionArcaea, IMPORTRANGE(sourceSheetName,"DevSettings!C5"),
  loadingText, SWITCH(
      DevSettings!$C$21,
      "한국어", "↻ 로드 중...",
      "English", "↻ Loading...",
      "日本語", "↻ ロード中..."
  ),
  SWITCH(
    IFERROR(ERROR.TYPE(latestVersionArcaea), 0),
    4, loadingText,
    10, loadingText,
    0, 
    latestVersionArcaea,
    SWITCH(
      DevSettings!$C$21,
      "한국어", "✘ 오류 코드: ",
      "English", "✘ Error Code: ",
      "日本語", "✘ エラーコード: "
    )&IFERROR(ERROR.TYPE(latestVersionArcaea), 0)
  )
)`}
];

function getLatestVersion() {
  latestVersionCells.forEach(({ cell, formula }) => {
    cell.clear({ contentsOnly: true });
    cell.setFormula(formula);
  });
}