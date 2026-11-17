import ArcaeaCore
import SwiftUI

/// What automatic tracking is doing right now, in one glance.
struct TrackingStatusCard: View {
    @Environment(OnlineRuntime.self) private var runtime
    @Environment(AppNavigation.self) private var navigation
    /// Offers the way to the screens that fix "not set up" and "needs sign-in". Off inside Settings, where those
    /// screens are the next rows.
    var showsActions = false

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
            case .notSetUp: String(localized: "Tracker not set up")
            case .needsSignIn: String(localized: "Tracker needs to sign in again")
            case .stalled: String(localized: "Arcaea is open, but the Shortcut stopped checking")
            case .tracking: String(localized: "Tracking plays")
            case .closing: String(localized: "Arcaea closed · final checks")
            case .idle: String(localized: "Waiting for Arcaea to open")
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
                if showsActions, phase == .notSetUp || phase == .needsSignIn {
                    if phase == .notSetUp {
                        Text("Sign in with a tracker account and build the Shortcut, and each play is saved as you finish it.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        Button(phase == .needsSignIn ? "Sign in again" : "Tracker account") { navigation.openSettings(.trackerAccount) }
                            .accessibilityIdentifier("tracking.openTracker")
                        if phase == .notSetUp { Button("Shortcut setup") { navigation.openSettings(.shortcuts) }.accessibilityIdentifier("tracking.openShortcuts") }
                    }.buttonStyle(.bordered).controlSize(.small).padding(.top, 2)
                }
                if let status, phase != .notSetUp {
                    if phase == .tracking, let next = status.nextPollAt, next > timeline.date { row("Next check", next.formatted(date: .omitted, time: .standard)) }
                    row("Last check", lastCheck(status, now: timeline.date))
                    row("Last new play", status.lastNewPlayAt.map { relative($0, now: timeline.date) } ?? String(localized: "None yet"))
                    if let cooldown = status.cooldownUntil, cooldown > timeline.date { row("Server asked to wait until", cooldown.formatted(date: .omitted, time: .standard)) }
                }
            }
        }
        .task { while !Task.isCancelled { await runtime.refreshStatus(); try? await Task.sleep(for: .seconds(15)) } }
    }

    private func lastCheck(_ status: TrackingStatus, now: Date) -> String {
        guard let attempt = status.lastAttemptAt else { return String(localized: "Never") }
        return relative(attempt, now: now) + (status.lastStatus.map { " · " + label($0) } ?? "")
    }
    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) }.font(.subheadline)
    }
    private func relative(_ date: Date, now: Date) -> String {
        now.timeIntervalSince(date) < 60 ? String(localized: "Just now") : date.formatted(.relative(presentation: .named))
    }
    private func label(_ status: FetchStatus) -> String {
        switch status {
        case .success: String(localized: "new play")
        case .unchanged: String(localized: "nothing new")
        case .offline: String(localized: "offline")
        case .rateLimited, .cooldown: String(localized: "told to wait")
        case .authenticationRequired, .attentionRequired, .wrongAccount: String(localized: "needs sign-in")
        case .deadlineExceeded: String(localized: "timed out")
        default: String(localized: "failed")
        }
    }
}
