import ArcaeaCore
import SwiftUI

extension ClearType {
    /// The hue of the game's own badge for each clear, brightened so a small dot reads on light and dark backgrounds.
    var color: Color {
        func rgb(_ hex: UInt32) -> Color {
            Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        }
        return switch self {
        case .trackLost: rgb(0xA8455F)
        case .easy: rgb(0x2E8C98)
        case .normal: rgb(0x8E4A9A)
        case .hard: rgb(0xD03468)
        case .fullRecall: rgb(0xC04DC8)
        case .pureMemory: rgb(0x4A86D0)
        }
    }
}

/// A clear lamp: a coloured dot and a name. Deliberately not a capsule, so it never reads as a difficulty badge.
/// Shows nothing when the clear is unknown.
struct ClearLamp: View {
    let clear: ClearType?
    /// Scales the lamp with its surroundings (the Best 50 cards shrink their text with the card). 1 is the normal size.
    var scale: CGFloat = 1
    var body: some View {
        if let clear {
            HStack(spacing: 4 * scale) {
                Circle().fill(clear.color).frame(width: 8 * scale, height: 8 * scale)
                Text(DisplayFormat.clear(clear)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(scale == 1 ? .caption.weight(.medium) : .system(size: 12 * scale, weight: .medium)).foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore).accessibilityLabel(DisplayFormat.clear(clear))
        }
    }
}

/// What a play did to the chart's best: the one thing worth knowing right after playing.
/// A new best stands out by weight, not by colour: green and red already mean a difficulty.
struct PlayChangeLabel: View {
    let change: PlayChange
    var body: some View {
        Group {
            switch change {
            case .first: Text("First saved play").foregroundStyle(.secondary)
            case .newBest(let points): HStack(spacing: 3) { Image(systemName: "arrow.up"); Text("New best +\(DisplayFormat.score(points))") }.fontWeight(.bold)
            case .tie: Text("Same as best").foregroundStyle(.secondary)
            case .below(let points): Text(verbatim: "−\(DisplayFormat.score(points))").foregroundStyle(.secondary)
            }
        }.font(.caption).monospacedDigit().lineLimit(1)
    }
}

/// Pure / Far / Lost as a proportion bar with the counts underneath.
struct JudgmentBar: View {
    let judgments: Judgments
    private var parts: [(label: String, value: Int?, color: Color)] {
        [("PURE", judgments.pure, .purple), ("FAR", judgments.far, .orange), ("LOST", judgments.lost, .pink)]
    }
    var body: some View {
        VStack(spacing: 8) {
            let counts = parts.compactMap(\.value), total = counts.reduce(0, +)
            // A bar with a part missing would misstate the play, so it is drawn only when all three are known.
            if counts.count == parts.count, total > 0 {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(parts, id: \.label) { part in
                            if let value = part.value, value > 0 {
                                Rectangle().fill(part.color).frame(width: max(3, (proxy.size.width - 4) * CGFloat(value) / CGFloat(total)))
                            }
                        }
                    }.frame(width: proxy.size.width, alignment: .leading)
                }.frame(height: 8).clipShape(Capsule()).accessibilityHidden(true)
            }
            HStack {
                ForEach(parts, id: \.label) { part in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(part.label).font(.caption2.bold()).foregroundStyle(part.color)
                        Text(part.value.map { $0.formatted() } ?? "—").font(.headline.monospacedDigit())
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
