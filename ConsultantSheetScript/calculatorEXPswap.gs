// 데이터 유효성 검사 규칙 (%, 정수)
const percent_validation = SpreadsheetApp.newDataValidation()
  .requireFormulaSatisfied('=AND(LEFT(G6,LEN(G6)-1)*1<=100, LEFT(G6,LEN(G6)-1)*1>=0)')
  .setAllowInvalid(false)
  .build()

const integer_validation = SpreadsheetApp.newDataValidation()
  .requireFormulaSatisfied('=AND(G6<=XLOOKUP(F6,$AA$6:$AA$36,$AC$6:$AC$36), G6>=0)')
  .setAllowInvalid(false)
  .build()

// 숫자 서식
const percent_format = "0%"
const integer_format = "0"

const validations   = [percent_validation, integer_validation]
const formats       = [percent_format, integer_format]

// 체크박스 좌표
const CheckboxRange = "E3"
const calcSheet = getTabWithId(TAB_NAME_DICTIONARY.CALCULATORS)

function calcOnEdit(e){
  if (e.range.getSheet().getName() !== TAB_NAME_DICTIONARY.CALCULATORS) return
  if (e.range.getA1Notation() !== CheckboxRange) return

  // 정수 <-> 퍼센트 값 저장된 열 값 받아올 변수
  let swap_values

  // True, False를 1, 0으로 변경 (validation, format 쉽게 가져오려고)
  // lastRow를 PartnerData 페이지에서 가져오고도 싶엇는데 일단은
  const checkbox = Number(calcSheet.getRange(CheckboxRange).getValue())
  const lastRow = calcSheet.getLastRow() - 1

  Logger.log(checkbox)

  // 체크박스 활성화 (정수 값 가져오기) 
  if (checkbox)
    swap_values = calcSheet.getRange(`BB6:BB${lastRow}`).getValues()

  //    ''   비활성화 (% 값 가져오기)
  else
    swap_values = calcSheet.getRange(`BA6:BA${lastRow}`).getValues()

  // 셀 값 먼저 바꾸기 (setValues가 적용되는 게 느려서 값이 실제로 바뀌기 전에 Format이 바껴 더러워보여서 무조건 먼저 해야 함)
  calcSheet.getRange(`G6:G${lastRow}`).setValues(swap_values)
  calcSheet.getRange(`G6:G${lastRow}`).setDataValidation(validations[checkbox])
  calcSheet.getRange(`G6:G${lastRow}`).setNumberFormat(formats[checkbox])
}