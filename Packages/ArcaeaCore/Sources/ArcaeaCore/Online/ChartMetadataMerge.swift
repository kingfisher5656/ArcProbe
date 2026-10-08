import Foundation

public enum ChartMetadataMerge {
    public static func merge(_ incoming: [ChartMetadata], catalog: ChartCatalog) -> [ChartMetadata] {
        incoming.map { chart in
            let old = catalog[chart.id]
            return ChartMetadata(id: chart.id, constant: chart.constant ?? old?.constant,
                isOutdated: chart.constant == nil ? old?.isOutdated ?? false : chart.isOutdated,
                level: chart.level ?? old?.level, difficultyLabel: chart.difficultyLabel ?? old?.difficultyLabel,
                noteCount: chart.noteCount ?? old?.noteCount, title: chart.title ?? old?.title,
                artist: chart.artist ?? old?.artist, artworkIdentifier: chart.artworkIdentifier ?? old?.artworkIdentifier,
                provenance: old?.provenance ?? chart.provenance)
        }
    }
}
