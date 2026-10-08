import Foundation
@testable import ArcaeaCore

let testAccount = AccountID("main-123")
let otherAccount = AccountID("observer-456")
let testChart = ChartID(songID: "synthetic", difficulty: .future)
let testDate = Date(timeIntervalSince1970: 1_800_000_000)

func observation(_ id: String, score: Int = 9_800_000, at: Int64? = 1_800_000_000,
                 account: AccountID = testAccount, chart: ChartID = testChart,
                 judgments: Judgments? = nil, clear: ClearType? = nil,
                 bestClear: ClearType? = nil, source: ObservationSource = .officialRecent) -> ScoreObservation {
    ScoreObservation(id: ObservationID(id), accountID: account, chartID: chart, source: source,
        values: ScoreValues(score: score, playedAt: at.map { SourceTimestamp(value: $0, unit: .seconds) },
                            judgments: judgments, playClear: clear, bestClear: bestClear), firstSeenAt: testDate,
        identityConfidence: source == .manual ? .manual : .sourceEvent)
}

func temporaryArchiveURL() -> URL {
    // Keep fixtures and their WAL files in the authorized project, not the user's archive.
    let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return package.appendingPathComponent(".test-archives/\(UUID().uuidString)/archive.sqlite")
}
