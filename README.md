# ArcProbe

iPadOS에서 구동되는 아르케아 점수 기록/관리 어플입니다.

- Arcaea Online과의 점수, B50, 포텐 그래프 동기화
- 별도의 친구 계정과 iOS 단축어 자동화를 이용한 최근 플레이 자동 기록
- B50 포텐 계산, B50 JPG 내보내기, 전체 점수 관리, 포텐 변화 그래프
- Arcaea consultant 구글 시트와의 점수 가져오기/보내기
- 수동 점수 입력 및 수정

해당 프로젝트 내의 모든 코드는 AI를 통해 생성되었습니다. 실용적인 프로그램이라기보다 무엇이 가능한지 실증하는 테스트 형태의 프로그램으로 봐주시길 부탁드립니다.

iPadOS 18에서 테스트되었습니다.

## 설치 및 사용법

1. SideStore를 통해 Releases의 IPA 파일을 설치합니다. (LiveContainer 내 설치는 지원하지 않음)
2. ArcProbe 우측 상단 톱니바퀴(Settings) → **Main account** 에서 Arcaea Online을 구독 중인 주 계정으로 로그인하고, **Import scores and potential history** 를 눌러 기록을 가져옵니다.
3. Settings → **Tracker account** 에서 주 계정을 친구로 등록해 둔 별도의 계정으로 로그인합니다. 로그인이 만료되어도 자동으로 다시 로그인되게 하려면 **Save password for automatic re-login** 을 설정합니다.
4. 단축어 앱에서 아래 단축어와 자동화 두 개를 만듭니다. 앱 안의 Settings → **Shortcut setup** 에도 같은 내용이 있습니다.

**단축어 "ArcProbe tracking"**

| # | 동작 | 설정 |
|---|---|---|
| 1 | Start Arcaea Tracking | |
| 2 | 반복 | 1000번 |
| 3 | &nbsp;&nbsp;Check Recent Play | Session = 1번 동작의 결과 |
| 4 | &nbsp;&nbsp;조건문: Check Recent Play 결과가 1보다 작으면 → 이 단축어 중단 | |
| 5 | &nbsp;&nbsp;대기 | 시간 = Check Recent Play의 결과 |
| 6 | 반복 종료 | |

**자동화**

| 조건 | 실행 |
|---|---|
| Arcaea 앱이 열릴 때 | 단축어 "ArcProbe tracking" 실행 |
| Arcaea 앱이 닫힐 때 | Stop Arcaea Tracking |

두 자동화 모두 "즉시 실행"으로 설정합니다.

이후 Arcaea가 열려 있는 동안 65~80초마다 최근 기록을 확인해 ArcProbe에 저장하고, Arcaea를 닫으면 두 번 더 확인한 뒤 단축어가 스스로 종료됩니다. 확인 주기와 종료 시점은 앱이 정하므로 단축어를 수정할 필요가 없습니다. Arcaea를 빠르게 여러 번 닫았다 열어도 가장 최근에 시작된 단축어 하나만 남고 확인 주기는 그대로 이어집니다.

0.2.x에서 업데이트하는 경우 기존 단축어(Set Tracking Active / Get Tracking Status / Fetch Recent Play를 쓰던 것)는 더 이상 동작하지 않습니다. 삭제하고 위 단축어로 다시 만들어 주세요.

iPadOS 27 이상에서는 자동화로 실행된 단축어가 오래 실행되지 못하거나, 제어 센터를 내릴 때 "앱이 닫힐 때" 자동화가 실행되는 문제가 있을 수 있습니다. 이 경우 Arcaea를 다시 열면 추적이 다시 시작됩니다.

---

## What it does

- **Best 50** with estimated potential, and export as JPG or CSV.
- **Scores**: every chart best, with manual add, edit, delete and undo.
- **Recent**: plays recorded automatically while Arcaea is open.
- **Potential**: official history from Arcaea Online plus a local estimate for plays since the last import.
- **Consultant sheet** (Settings): import mobile scores from, or send them to, your Arcaea consultant workbook in Google Sheets. Always previewed and confirmed first.
- **Backup**: scores as JSON, downloaded cover art as a separate file.

Everything is stored on the device. ArcProbe only reads from Arcaea Online; it never uploads scores or touches the game.

## Automatic tracking

See [docs/shortcuts.md](docs/shortcuts.md) for the setup and for how the loop behaves when Arcaea is reopened quickly, when the connection drops, or when the tracker login expires.

## Build

No third-party tooling is needed besides Xcode. The Xcode project is generated from the files on disk.

```sh
swift test --package-path Packages/ArcaeaCore
python3 scripts/generate-project.py
xcodebuild test -project ArcaeaOffline.xcodeproj -scheme ArcaeaOffline \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)'
zsh scripts/package-ipa.sh   # unsigned IPA in artifacts/, sign and install with SideStore
```

## Notes

- Export a JSON backup (Settings → Backup & restore) before reinstalling or changing the signing identity.
- Potential values computed by ArcProbe are estimates from a dated chart-constant table and can differ from the server.
- After a game update adds songs, use Settings → Charts & cover art → **Update constants and levels** to fetch the new constants, levels and song names from the Arcaea community wiki.
- Google sign-in for the sheet feature is in Google's testing mode, so it asks to reconnect about once a week. See [docs/google-sheets-setup.md](docs/google-sheets-setup.md).
- Attribution and licenses: [NOTICE.md](NOTICE.md), [B50 export fonts](docs/export-fonts.md).
