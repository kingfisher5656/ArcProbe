function importAll() {
  importScoreInputAndHistory();
  importSettings();
  importPartners();
}

function importScoreInputAndHistory() {
  importScoreInput();
  importScoreHistory();

  const inputMsg2 = CURRENT_SPREADSHEET.getRangeByName('MenuTranslation!I9').getValue();
  Browser.msgBox(inputMsg2);
}

function importScoreInput() { 

  var scoreInputSheet = getTabWithId(TAB_NAME_DICTIONARY.SCORE_INPUT);

  var datacheck = getTabWithId('DevSettings').getRange("F27").getValue();
  if (datacheck !== true) {
    const inputMsg1 = CURRENT_SPREADSHEET.getRangeByName('MenuTranslation!I8').getValue();
    Browser.msgBox(inputMsg1);
    return;
  }

  const scoredatasheet = getTabWithId('ScoreData');
  var songInput = scoredatasheet.getRange("P2:P").getValues().flat().map(String);
  var scoreInputMobile = scoredatasheet.getRange("Q2:Q").getValues().flat();
  var scoreInputNST = scoredatasheet.getRange("R2:R").getValues().flat();
  var scoreInputNSJ = scoredatasheet.getRange("S2:S").getValues().flat();
  var scoreInputMobileLost = scoredatasheet.getRange("T2:T").getValues().flat();
  var songDB = scoreInputSheet.getRange("B:B").getValues().flat().map(String);

  var songDBMap = {};
  songDB.forEach((name, idx) => {
    if (name) {
      songDBMap[name] = idx;
    }
  });

  var colHValues = scoreInputSheet.getRange(1, 8, songDB.length, 1).getValues();
  var colIValues = scoreInputSheet.getRange(1, 9, songDB.length, 1).getValues();
  var colNValues = scoreInputSheet.getRange(1, 14, songDB.length, 1).getValues();
  var colPValues = scoreInputSheet.getRange(1, 16, songDB.length, 1).getValues();

  songInput.forEach((song, index) => {
    if (song && songDBMap[song] !== undefined) {
      var rowIndex = songDBMap[song];
      colHValues[rowIndex][0] = scoreInputMobile[index];
      colIValues[rowIndex][0] = scoreInputMobileLost[index];
      colNValues[rowIndex][0] = scoreInputNST[index];
      colPValues[rowIndex][0] = scoreInputNSJ[index];
    }
  });

  scoreInputSheet.getRange(1, 8, songDB.length, 1).setValues(colHValues);
  scoreInputSheet.getRange(1, 9, songDB.length, 1).setValues(colIValues);
  scoreInputSheet.getRange(1, 14, songDB.length, 1).setValues(colNValues);
  scoreInputSheet.getRange(1, 16, songDB.length, 1).setValues(colPValues);
}

function importScoreHistory() {
    var spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
    var sourceSheet = spreadsheet.getSheetByName("ScoreData");
    var targetSheet = spreadsheet.getSheetByName("ScoreHistory");

    // 복사할 범위 정의 (ScoreData U:BM)
    const SOURCE_START_COL = 21;
    const SOURCE_END_COL = 65;
    const NUM_COLUMNS = SOURCE_END_COL - SOURCE_START_COL + 1;

    // 복사 대상 범위 정의 (ScoreHistory G:AY)
    const TARGET_START_COL = 7;
    const lastRow = sourceSheet.getLastRow();
    
    // 데이터 가져오기 (Source: ScoreData R:BJ)
    const sourceRange = sourceSheet.getRange(1, SOURCE_START_COL, lastRow, NUM_COLUMNS);
    const valuesToCopy = sourceRange.getValues();

    // 데이터 덮어쓰기 (Target: ScoreHistory G:AY)
    const targetRange = targetSheet.getRange(1, TARGET_START_COL, lastRow, NUM_COLUMNS);
    targetRange.setValues(valuesToCopy);
}

function importSettings() {
  
  var spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
  var sourceSheet = getTabWithId(TAB_NAME_DICTIONARY.PREV_SETTINGS);

  var datacheck = getTabWithId('DevSettings').getRange("F29").getValue();
  var prevUiLanguage = sourceSheet.getRange("E7").getValue();
  var currUiLanguage = sourceSheet.getRange("D7").getValue();

  if (datacheck !== true || prevUiLanguage !== currUiLanguage) {
    const inputMsg1 = CURRENT_SPREADSHEET.getRangeByName('MenuTranslation!I10').getValue();
    Browser.msgBox(inputMsg1);
    return;
  }

  var startRow = 6;
  var lastRow = sourceSheet.getLastRow();

  var dataRange = sourceSheet.getRange(startRow, 5, lastRow - startRow + 1, 2); // E열(5), F열(6) 포함 2개 열
  var values = dataRange.getValues(); // [E열값, F열값] 배열의 배열

  // F열의 셀 주소에 E열의 값을 덮어씌웁니다.
  for (var i = 0; i < values.length; i++) {
    var valueToApply = values[i][0];       // E열의 값
    var targetRangeString = values[i][1];  // F열의 값

    // Browser.msgBox(valueToApply)

    // F열에 주소가 있고 E열에 값이 있는 경우에만 처리
    // valueToApply가 빈 문자열일 수 있으므로 null/undefined만 체크합니다.
    if (targetRangeString && valueToApply !== undefined && valueToApply !== null) {
      try {
        // 대상 범위 (예: '메인 [Main]!$H$5', '점수 입력 [Score Input]!$D$3')에서
        // 시트 이름과 셀 주소를 분리합니다.
        var parts = targetRangeString.split('!');
        var sheetName;
        var cellAddress;

        if (parts.length > 1) { // 시트 이름과 셀 주소가 모두 명시된 경우 (예: '시트이름!A1')
          sheetName = parts[0].replace(/^'+|'+$/g, "");
          cellAddress = parts[1].replace(/\$/g, ''); // '$' 기호 제거
        } else { // 시트 이름 없이 셀 주소만 명시된 경우 (이 경우 PrevSettings 시트 자신이 대상이 됨)
          sheetName = sourceSheet.getName(); // 원본 시트의 이름을 사용
          cellAddress = parts[0].replace(/\$/g, '');
        }

        // 값을 적용할 대상 시트를 현재 스프레드시트에서 가져옵니다.
        var targetSheet = spreadsheet.getSheetByName(sheetName);

        if (targetSheet) {
          // 대상 셀에 값 적용
          targetSheet.getRange(cellAddress).setValue(valueToApply);
          // Logger.log("적용 완료: " + targetRangeString + " 에 '" + valueToApply + "' 값 적용."); // 디버깅용, 필요시 주석 해제
        } else {
          Logger.log("경고: 현재 스프레드시트에서 대상 시트를 찾을 수 없습니다 - " + sheetName + " (원본 F열 값: " + targetRangeString + ")");
        }
      } catch (e) {
        Logger.log("오류: " + targetRangeString + " 처리 중 에러 발생 - " + e.message);
      }
    }
  }

    const inputMsg2 = CURRENT_SPREADSHEET.getRangeByName('MenuTranslation!I11').getValue();
    Browser.msgBox(inputMsg2);
  }

function importPartners() {
  const partnerleveldatasheet = getTabWithId(TAB_NAME_DICTIONARY.CALCULATORS);

  var datacheck = getTabWithId('DevSettings').getRange("F29").getValue();
  var litecheck = getTabWithId('DevSettings').getRange("F26").getValue();
  if (datacheck !== true || litecheck !== false) {
    const inputMsg1 = CURRENT_SPREADSHEET.getRangeByName('MenuTranslation!I12').getValue();
    Browser.msgBox(inputMsg1);
    return;
  }

  var ownedToggle = partnerleveldatasheet.getRange("Y2").getValue();
  var expToggle = partnerleveldatasheet.getRange("Y3").getValue();
  var stepTempest = partnerleveldatasheet.getRange("Z2").getValue();
  var stepFatalis = partnerleveldatasheet.getRange("Z3").getValue();
  var partnerId = partnerleveldatasheet.getRange("W6:W").getValues().flat();
  var partnerOwned = partnerleveldatasheet.getRange("X6:X").getValues().flat();
  var partnerLv = partnerleveldatasheet.getRange("Y6:Y").getValues().flat();
  var partnerExp = partnerleveldatasheet.getRange("Z6:Z").getValues().flat();
  var partnerDB = partnerleveldatasheet.getRange("B6:B").getValues().flat();

  partnerleveldatasheet.getRange("E2").setValue(ownedToggle);
  partnerleveldatasheet.getRange("E3").setValue(expToggle);
  partnerleveldatasheet.getRange("J2").setValue(stepTempest);
  partnerleveldatasheet.getRange("J3").setValue(stepFatalis);

  var partnerDBMap = {};
  partnerDB.forEach((name, idx) => {
    if (name) {
      partnerDBMap[name] = idx;
    }
  });

  var colEValues = partnerleveldatasheet.getRange(6, 5, partnerDB.length, 1).getValues();
  var colFValues = partnerleveldatasheet.getRange(6, 6, partnerDB.length, 1).getValues();
  var colGValues = partnerleveldatasheet.getRange(6, 7, partnerDB.length, 1).getValues();

  partnerId.forEach((partner, index) => {
    if (partner && partnerDBMap[partner] !== undefined) {
      var rowIndex = partnerDBMap[partner];
      colEValues[rowIndex][0] = partnerOwned[index];
      colFValues[rowIndex][0] = partnerLv[index];
      colGValues[rowIndex][0] = partnerExp[index];
    }
  });

  partnerleveldatasheet.getRange(6, 5, partnerDB.length, 1).setValues(colEValues);
  partnerleveldatasheet.getRange(6, 6, partnerDB.length, 1).setValues(colFValues);
  partnerleveldatasheet.getRange(6, 7, partnerDB.length, 1).setValues(colGValues);

  const inputMsg2 = CURRENT_SPREADSHEET.getRangeByName('MenuTranslation!I13').getValue();
  Browser.msgBox(inputMsg2);
}