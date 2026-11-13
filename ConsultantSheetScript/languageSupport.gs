const LANGUAGE_DROPDOWN = {
  SONG_NAME: "H5",
  UI: "J5"
};

const LAGNUAGE_FONT = {
  [LANGUAGE_CLASS.KO]: "Asta Sans",
  [LANGUAGE_CLASS.EN]: "Asta Sans",
  [LANGUAGE_CLASS.JP]: "Noto Sans JP",
};

function languageChange(e) {

  const editedSheetName = e.range.getSheet().getName();
  const editedCell = e.range.getA1Notation();
  const mainSheet = getTabWithId(TAB_NAME_DICTIONARY.MAIN);

  if (!mainSheet) return;
  if (editedSheetName !== mainSheet.getName()) return;

  if (editedCell === LANGUAGE_DROPDOWN.UI) {
    refreshDropdownFormula();
  }

}

function refreshDropdownFormula() {

  for (const [sheetName, formulaMap] of Object.entries(MULTI_LINGUAL_DROPDOWN)) {
    const sheet = getTabWithId(sheetName);
    for (const [cellA1, formula] of Object.entries(formulaMap)) {
      sheet.getRange(cellA1).setFormula(formula);
    }
  }
}

function changeSongNameFont() {
  const songNameLanguage = getTabWithId(TAB_NAME_DICTIONARY.MAIN)
                            .getRange(LANGUAGE_DROPDOWN.SONG_NAME).getValue();
  const fontName = LAGNUAGE_FONT[songNameLanguage];
  console.log(`${fontName}`);
  const songNameRange = {
    [TAB_NAME_DICTIONARY.SCORE_INPUT]: [
      "C5:C",
    ],
    [TAB_NAME_DICTIONARY.ARCAEA_ONLINE]: [
      "G11:G20",
      "M11:N20",
    ],
    [TAB_NAME_DICTIONARY.CONSULTANT]: [
      "D8:D40",
      "D46:D55",
      "J8:J40",
      "J46:J55",
    ],
    [TAB_NAME_DICTIONARY.MY_SCORE_MOBILE]: [
      "D3:D",
      "O3:O",
      "Z3:Z",
      "AK3:AK",
      "AV3:AV",
    ],
    [TAB_NAME_DICTIONARY.MY_SCORE_NS_T]: [
      "D3:D",
      "O3:O",
      "Z3:Z",
      "AK3:AK",
    ],
    [TAB_NAME_DICTIONARY.MY_SCORE_NS_J]: [
      "D3:D",
      "O3:O",
      "Z3:Z",
      "AK3:AK",
    ],
    [TAB_NAME_DICTIONARY.BP_TABLE]: [
      "D6:L",
    ],
    [TAB_NAME_DICTIONARY.SONG_SEARCH]: [
      "D3:G3",
      "C4:G4",
      "I2:L6",
    ],
  }
  Object.entries(songNameRange).forEach(([sheetName, rangeTextValues]) => {
    const targetSheet = getTabWithId(sheetName);
    rangeTextValues.forEach((rangeText) => {
      targetSheet.getRange(rangeText).setFontFamily(fontName);
    });
  });
}

function changeUiFont() {

  const sheets = CURRENT_SPREADSHEET.getSheets().filter(sheet => 
    Object.values(TAB_NAME_DICTIONARY).some(value => sheet.getName().includes(value))
  );
  const uiLanguage = CURRENT_SPREADSHEET.getSheetByName(TAB_NAME_DICTIONARY.MAIN)
                                        .getRange(LANGUAGE_DROPDOWN.UI).getValue();
  const fontName = LAGNUAGE_FONT[uiLanguage];

  const richTextRange = {
    [TAB_NAME_DICTIONARY.MAIN]: [
      "G2:I2",
      "G3:J4",
      "G5:G6",
      "H3:I13",
      "I5:I6",
      "H32:J32",
    ],
  }

  backups = [];
  Object.entries(richTextRange).forEach(([sheetName, rangeTextValues]) => {
    const targetSheet = getTabWithId(sheetName);
    rangeTextValues.forEach((rangeText) => {
      const rich = targetSheet.getRange(rangeText).getRichTextValues();
      backups.push({sheet: targetSheet, range: rangeText, rich});
    });
  });
  
  sheets.forEach(sheet => {
    const dataRange = sheet.getDataRange();
    dataRange.setFontFamily(fontName);
  });

  backups.forEach(({ sheet, range, rich }) => {
    if (rich) sheet.getRange(range).setRichTextValues(rich);
  });
}

function refreshFonts() {
  changeUiFont();
  changeSongNameFont();
}