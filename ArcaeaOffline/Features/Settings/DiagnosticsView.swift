import ArcaeaCore
import SwiftUI

struct DiagnosticsView: View {
    @Environment(ArchiveModel.self) private var model
    @State private var receipts: [ImportReceipt] = []
    var body: some View {
        List {
            Section("Archive status") { LabeledContent("Accounts", value: String(model.profiles.count)); LabeledContent("Effective plays", value: String(model.observations.count)); LabeledContent("Official potential points", value: String(model.officialHistory.count)); LabeledContent("Unrated constants", value: String(model.ranking?.missingConstants ?? 0)); LabeledContent("Unknown clear lamps", value: String(model.ranking?.unknownClears ?? 0)); LabeledContent("Rating rule", value: model.ranking?.ruleVersion ?? "arcpot-2026-09") }
            Section("Recent archive transactions") { ForEach(receipts.prefix(30), id: \.id) { receipt in VStack(alignment: .leading, spacing: 5) { Text(receipt.kind.rawValue.capitalized).font(.headline); Text(receipt.importedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary); Text("\(receipt.addedCount) added · \(receipt.duplicateCount) duplicate · \(receipt.addedPotentialCount) history points").font(.subheadline) } } }
            Section { Text("Diagnostics contain counts and timestamps only. Session cookies and passwords are never shown or exported.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Diagnostics").task { model.perform { receipts = try model.store.receipts(accountID: model.selectedAccountID).sorted { $0.importedAt > $1.importedAt } } }
    }
}
