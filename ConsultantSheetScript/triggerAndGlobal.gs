const SOURCE_SHEET_ID = "1aUhG8C-0wVsL_jMPwpkZ4hXMH5zN9sZDM_wGBb4On0w";

const CURRENT_SPREADSHEET = SpreadsheetApp.getActive();

const LANGUAGE_CLASS = {
  KO: "한국어", 
  EN: "English", 
  JP: "日本語"
};

const TAB_NAME_DICTIONARY = {
  MAIN: "메인 [Main]",
  SCORE_INPUT: "점수 입력 [Score Input]",
  CONSULTANT: "대시보드 [Dashboard]",
  MY_SCORE_MOBILE: "내 점수 [Score] (M)",
  MY_SCORE_NS_T: "내 점수 [Score] (NS-T)",
  MY_SCORE_NS_J: "내 점수 [Score] (NS-J)",
  BP_TABLE: "상수표 [CC Table]",
  SONG_SEARCH: "검색 [Search]",
  CALCULATORS: "계산기 [Tools]",
  // UPDATE_HISTORY: "업데이트 내역 [Changelog]",
  PREV_SETTINGS: "PrevSheetSettings",
  CREDITS: "Credits",
  ARCAEA_ONLINE: "Arcaea Online",
};

const MULTI_LINGUAL_DROPDOWN = {
  [TAB_NAME_DICTIONARY.SCORE_INPUT]: {
    "R3":   "=$S$4",
  },
  [TAB_NAME_DICTIONARY.ARCAEA_ONLINE]: {
    "I4":   "=$K$8",
  },
  [TAB_NAME_DICTIONARY.CONSULTANT]: {
    "C7":   "=$AB$18",
    "E2":   "=$AB$9",
    "E3":   "=$AB$14",
    "E7":   "=$AB$23",
    "E65":  "=$AB$27",
    "E76":  "=$AB$31",
    "E77":  "=$AB$36",
    "E78":  "=$AB$60",
    "N46":  "=$AB$56",
    "O49":  "=$AE$11",
    "R60":  "=$AE$6",
    "Q2":  "=$AE$22",
  },
  [TAB_NAME_DICTIONARY.BP_TABLE]: {
    "J2":   "=$S$7",
    "J3":   "=$S$11",
    "J4":   "=$S$38",
    "L2":   "=$S$56",
    "L3":   "=$S$51",
    "L4":   "=$S$52",
    "N2":   "=$S$35",
    "N3":   "=$S$33",
  },
  [TAB_NAME_DICTIONARY.SONG_SEARCH]: {
    "C4":   "=$D$26",
    "F6":   "=$G$36",
    "D10":  "=$G$41",
  },
  [TAB_NAME_DICTIONARY.CALCULATORS]: {
    "M18":  "=$V$6",
    "M19":  "=$V$7",
    "M23":  "=$AP$5",
  }
};

function onEdit(e) {
  calcOnEdit(e);
  consultantOnEdit(e);
  decimalOnEdit(e);
  languageChange(e);
}

function onOpen(e) {
  getSheetId(e);
  getLatestVersion(e);
}

function getTabWithId(tabType) {
  return targetTab = CURRENT_SPREADSHEET.getSheetByName(tabType);
}