const CONSULTANT_DROPDOWN = {
  PLATFORM: "E2",
  TARGET: "E56",
  LEVEL: "E57"
};

function consultantOnEdit(e) {

  const consultantSheet = getTabWithId(TAB_NAME_DICTIONARY.CONSULTANT);
  if (e.range.getSheet().getName() !== TAB_NAME_DICTIONARY.CONSULTANT) return;

  const targetCell = consultantSheet.getRange("E56");
  const levelCell = consultantSheet.getRange("E57");
  const pageCell = consultantSheet.getRange("E58");

  const ftrAndAboveTargetText = consultantSheet.getRange("AB31").getValue();
  const allRangeText = consultantSheet.getRange("AB36").getValue();
  const pageOneText = consultantSheet.getRange("AB60").getValue();

  switch (e.range.getA1Notation()) {
    case CONSULTANT_DROPDOWN.PLATFORM:
      targetCell.setValue(ftrAndAboveTargetText);
    case CONSULTANT_DROPDOWN.TARGET:
      levelCell.setValue(allRangeText);
    case CONSULTANT_DROPDOWN.LEVEL:
      pageCell.setValue(pageOneText);
  }

}

function decimalOnEdit(e) {
  const editedSheetName = e.range.getSheet().getName();
  const editedCell = e.range.getA1Notation();

  const settings = [
    {
      sheetKey: TAB_NAME_DICTIONARY.CONSULTANT,
      cell: "E3",
      criteriaCell: "E3",
      criteriaPotentialCell: "AB14",
      formatSettings: [
        { name: TAB_NAME_DICTIONARY.SCORE_INPUT, columns: [7, 12] },
        { name: TAB_NAME_DICTIONARY.MY_SCORE_MOBILE, columns: [3, 14, 25, 36, 47] },
        { name: TAB_NAME_DICTIONARY.MY_SCORE_NS_T, columns: [3, 14, 25, 36] },
        { name: TAB_NAME_DICTIONARY.MY_SCORE_NS_J, columns: [3, 14, 25, 36] }
      ]
    }
  ];

  settings.forEach(({ sheetKey, cell, criteriaCell, criteriaPotentialCell, formatSettings }) => {
    if (editedSheetName === sheetKey && editedCell === cell) {
      applyDecimalFormat(e.source, editedSheetName, criteriaCell, criteriaPotentialCell, formatSettings);
    }
  });
}

function applyDecimalFormat(sheetSource, sheetName, criteriaCell, criteriaPotentialCell, formatSettings) {
  const sheet = sheetSource.getSheetByName(sheetName);
  if (!sheet) return;

  const criteria = sheet.getRange(criteriaCell).getValue();
  const criteria_potential = sheet.getRange(criteriaPotentialCell).getValue();
  const decimalPlaces = (criteria === criteria_potential) ? 1 : 2;

  formatSettings.forEach(({ name, columns = [], cells = [] }) => {
    const targetSheet = sheetSource.getSheetByName(name);
    if (!targetSheet) return;

    formatColumns(targetSheet, columns, decimalPlaces);
    formatCells(targetSheet, cells, decimalPlaces);
  });
}

function formatColumns(sheet, columns, decimalPlaces) {
  const lastRow = sheet.getLastRow();
  const numberFormat = `0.${'0'.repeat(decimalPlaces)}`;
  if (lastRow > 0) {
    const ranges = columns.map(col => sheet.getRange(1, col, lastRow));
    ranges.forEach(range => range.setNumberFormat(numberFormat));
  }
}

function formatCells(sheet, cells, decimalPlaces) {
  if (!cells.length) return;
  const numberFormat = `0.${'0'.repeat(decimalPlaces)}`;
  cells.forEach(a1 => {
    const range = sheet.getRange(a1);
    range.setNumberFormat(numberFormat);
  });
}
