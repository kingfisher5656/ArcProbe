function scoreHistoryButton() {
  var consultantSheet = getTabWithId(TAB_NAME_DICTIONARY.CONSULTANT);
  var option = consultantSheet.getRange("R60").getValue();
  var optionDelete = consultantSheet.getRange("AE7").getValue();

  if (option == optionDelete) {
    deleteLastSavedHistory()
  } else {
    saveScoreHistory()
  }
}

function saveScoreHistory() {
    var sheet = getTabWithId("ScoreHistory");
    const TIME_ROW = 1; 
    const DATA_START_ROW = 3; 
    const SLOT_WIDTH = 3;
    const MAX_SLOTS = 15;
    const START_COL_INDEX = 7;
    const END_COL_INDEX = START_COL_INDEX + (MAX_SLOTS * SLOT_WIDTH) - 1;
    
    // 순환 이동에 필요한 계산
    const SHIFT_START_COL = START_COL_INDEX + SLOT_WIDTH;
    const SHIFT_COLUMNS_TO_MOVE = END_COL_INDEX - SHIFT_START_COL + 1;
    const NEW_DATA_COL = END_COL_INDEX - SLOT_WIDTH + 1;
    const SHIFT_TARGET_COL = START_COL_INDEX;

    // 카운터 셀 읽기 및 초기화
    var counterCell = sheet.getRange("A1");
    var nextColumnIndex = counterCell.getValue();
    if (typeof nextColumnIndex !== 'number' || nextColumnIndex < START_COL_INDEX) {
        nextColumnIndex = START_COL_INDEX;
    }

    // 점수 데이터 가져오기
    var lastRow = sheet.getLastRow();
    var sourceRange = sheet.getRange(DATA_START_ROW, 3, lastRow - DATA_START_ROW + 1, SLOT_WIDTH);
    var valuesToSave = sourceRange.getValues();

    valuesToSave.slice(0, 3).forEach((row, i) => {
      console.log(`row ${i + 1}:`, row);
    });
    
    var targetCol;
    var timeStampCol;

    if (nextColumnIndex <= END_COL_INDEX) {
        // Case 1: 초기 채우기 (1번째 ~ 15번째 저장)
        targetCol = nextColumnIndex;
        timeStampCol = nextColumnIndex;
        var targetRange = sheet.getRange(DATA_START_ROW, targetCol, valuesToSave.length, SLOT_WIDTH);
        targetRange.setValues(valuesToSave);

    } else {
        // Case 2: 순환 이동 및 저장 (16번째 저장부터)
        var ui = SpreadsheetApp.getUi();
        const msg2 = CURRENT_SPREADSHEET.getRangeByName('MenuTranslation!I16').getValue();
        var response = ui.alert(msg2, ui.ButtonSet.OK_CANCEL);
        if (response == ui.Button.CANCEL) {
            const msg3 = CURRENT_SPREADSHEET.getRangeByName('MenuTranslation!I17').getValue();
            Browser.msgBox(msg3);
            return;
        }

        //  데이터 이동
        var shiftSourceRange = sheet.getRange(TIME_ROW, SHIFT_START_COL, lastRow, SHIFT_COLUMNS_TO_MOVE);
        var shiftValues = shiftSourceRange.getValues();
        var shiftTargetRange = sheet.getRange(TIME_ROW, SHIFT_TARGET_COL, lastRow, SHIFT_COLUMNS_TO_MOVE);
        shiftTargetRange.setValues(shiftValues);
        
        // 새 데이터 저장
        targetCol = NEW_DATA_COL;
        timeStampCol = NEW_DATA_COL;
        var newTargetRange = sheet.getRange(DATA_START_ROW, targetCol, valuesToSave.length, SLOT_WIDTH);
        newTargetRange.setValues(valuesToSave);
        
        // 잔여 데이터 정리
        sheet.getRange(TIME_ROW, NEW_DATA_COL + SLOT_WIDTH, 2, 1).clearContent();
    }

    const msg1 = CURRENT_SPREADSHEET.getRangeByName('MenuTranslation!I15').getValue();
    Browser.msgBox(msg1);
    
    // 실행 시각 기록
    if (timeStampCol) {
        var formattedDate = Utilities.formatDate(
            new Date(), 
            SpreadsheetApp.getActiveSpreadsheet().getSpreadsheetTimeZone(), 
            "yy/MM/dd HH:mm"
        );
        
        sheet.getRange(TIME_ROW, timeStampCol).setValue(formattedDate);
    }
}

function deleteLastSavedHistory() {
    var sheet = getTabWithId("ScoreHistory");
    var counterCell = sheet.getRange("A1");
    var nextColumnIndex = counterCell.getValue();
    const SLOT_WIDTH = 3;
    const START_COL_INDEX = 7;
    
    // 카운터 값 검증 (최소 G열 인덱스보다 커야 함)
    if (typeof nextColumnIndex !== 'number' || nextColumnIndex <= START_COL_INDEX) {
        const msg4 = CURRENT_SPREADSHEET.getRangeByName('MenuTranslation!I18').getValue();
        Browser.msgBox(msg4, Browser.Buttons.OK);
        return;
    }

    // 경고문 출력
    var ui = SpreadsheetApp.getUi();
    const msg5 = CURRENT_SPREADSHEET.getRangeByName('MenuTranslation!I19').getValue();
    var response = ui.alert(msg5, ui.ButtonSet.OK_CANCEL);
    if (response == ui.Button.CANCEL) {
        const msg6 = CURRENT_SPREADSHEET.getRangeByName('MenuTranslation!I20').getValue();
        Browser.msgBox(msg6, Browser.Buttons.OK);
        return;
    }

    // 데이터 삭제
    var deleteStartCol = nextColumnIndex - SLOT_WIDTH;
    var lastRow = sheet.getLastRow();
    var deleteRange = sheet.getRange(1, deleteStartCol, lastRow, SLOT_WIDTH);
    deleteRange.clearContent();
    const msg7 = CURRENT_SPREADSHEET.getRangeByName('MenuTranslation!I21').getValue();
    Browser.msgBox(msg7, Browser.Buttons.OK);
}