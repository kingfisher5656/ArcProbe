import ArcaeaCore
import SwiftUI

/// What automatic tracking is doing right now, in one glance.
struct TrackingStatusCard: View {
    @Environment(OnlineRuntime.self) private var runtime

    enum Phase: Equatable {
        case notSetUp, needsSignIn, stalled, tracking, closing, idle
        init(configured: Bool, needsAttention: Bool, status: TrackingStatus?, now: Date) {
            if needsAttention { self = .needsSignIn }
            else if !configured { self = .notSetUp }
            else if let status, status.isActive { self = status.isStalled(now: now) ? .stalled : .tracking }
            else if let status, status.closingPollsRemaining > 0, let closed = status.closedAt,
                    now.timeIntervalSince(closed) < TrackingPolicy.closingLimit, status.session != nil { self = .closing }
            else { self = .idle }
        }
        var title: String {
            switch self {
            case .notSetUp: "Tracker not set up"
            case .needsSignIn: "Tracker needs to sign in again"
            case .stalled: "Arcaea is open, but the Shortcut stopped checking"
            case .tracking: "Tracking plays"
            case .closing: "Arcaea closed · final checks"
            case .idle: "Waiting for Arcaea to open"
            }
        }
        var systemImage: String {
            switch self {
            case .notSetUp: "circle.dashed"
            case .needsSignIn: "exclamationmark.triangle.fill"
            case .stalled: "exclamationmark.circle.fill"
            case .tracking: "dot.radiowaves.left.and.right"
            case .closing: "hourglass"
            case .idle: "moon.zzz"
            }
        }
        var color: Color {
            switch self {
            case .needsSignIn: .red
            case .stalled: .orange
            case .tracking: .green
            case .notSetUp, .closing, .idle: .secondary
            }
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { timeline in
            let status = runtime.trackingStatus
            let phase = Phase(configured: runtime.recentConfiguration != nil, needsAttention: runtime.recentNeedsAttention, status: status, now: timeline.date)
            VStack(alignment: .leading, spacing: 6) {
                Label(phase.title, systemImage: phase.systemImage).font(.headline).foregroundStyle(phase.color)
                    .accessibilityIdentifier("tracking.phase")
                if phase == .stalled {
                    Text("Reopen Arcaea to restart the loop. If this keeps happening, check the automation in Shortcuts.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let status, phase != .notSetUp {
                    if phase == .tracking, let next = status.nextPollAt, next > timeline.date { row("Next check", next.formatted(date: .omitted, time: .standard)) }
                    row("Last check", status.lastAttemptAt.map { relative($0, now: timeline.date) + (status.lastStatus.map { " · " + label($0) } ?? "") } ?? "Never")
                    row("Last new play", status.lastNewPlayAt.map { relative($0, now: timeline.date) } ?? "None yet")
                    if let cooldown = status.cooldownUntil, cooldown > timeline.date { row("Server asked to wait until", cooldown.formatted(date: .omitted, time: .standard)) }
                }
            }
        }
        .task { while !Task.isCancelled { await runtime.refreshStatus(); try? await Task.sleep(for: .seconds(15)) } }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) }.font(.subheadline)
    }
    private func relative(_ date: Date, now: Date) -> String {
        now.timeIntervalSince(date) < 60 ? "Just now" : date.formatted(.relative(presentation: .named))
    }
    private func label(_ status: FetchStatus) -> String {
        switch status {
        case .success: "new play"
        case .unchanged: "nothing new"
        case .offline: "offline"
        case .rateLimited, .cooldown: "told to wait"
        case .authenticationRequired, .attentionRequired, .wrongAccount: "needs sign-in"
        case .deadlineExceeded: "timed out"
        default: "failed"
        }
    }
}
