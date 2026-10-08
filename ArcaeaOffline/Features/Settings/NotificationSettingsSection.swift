import ArcaeaCore
import SwiftUI
import UserNotifications

struct NotificationSettingsSection: View {
    @Environment(OnlineRuntime.self) private var runtime
    @Environment(ArchiveModel.self) private var model
    @State private var minimum = 65
    @State private var maximum = 80
    @State private var state = NotificationPulseState()
    var body: some View {
        Section {
            Stepper("Minimum: \(minimum) seconds", value: $minimum, in: 60...3600, step: 5)
                .onChange(of: minimum) { _, value in if maximum < value { maximum = value } }
            Stepper("Maximum: \(maximum) seconds", value: $maximum, in: minimum...3600, step: 5)
            Button("Save notification interval") { model.perform { try NotificationTracking.shared().configure(minimum: minimum, maximum: maximum); model.notice = "Notification interval saved" } }
            Button("Enable notifications") {
                Task { do {
                    let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
                    model.notice = granted ? "Notifications allowed. Configure the iOS 27 notification automation next." : "Notifications are disabled. Enable them in system Settings for ArcProbe."
                } catch { model.errorMessage = error.localizedDescription } }
            }
            LabeledContent("Notification chain", value: state.isActive ? "Active" : "Stopped")
            if let date = state.nextAt { LabeledContent("Next pulse", value: date.formatted(date: .omitted, time: .standard)) }
            Button("Start notification tracking") { Task { do { state = try await NotificationTracking.shared().start(runtime: runtime) } catch { model.errorMessage = error.localizedDescription } } }
            Button("Stop notification tracking", role: .destructive) { model.perform { try NotificationTracking.shared().stop(runtime: runtime); state = try NotificationTracking.shared().state() } }
            NavigationLink("Notification automation setup") { NotificationSetupView() }
        } header: { Text("Notification tracking · iOS 27+") } footer: { Text("Each pulse starts a fresh short automation, which schedules the next random interval. Delivery may be delayed by iOS or Focus. The existing iOS 18 Repeat/Wait method remains available.") }
        .task { model.perform { state = try NotificationTracking.shared().state(); minimum = state.minimumSeconds; maximum = state.maximumSeconds } }
    }
}

private struct NotificationSetupView: View {
    var body: some View {
        List {
            Section("1 · Arcaea opens") { Text("Run Start Notification Tracking. Enable ArcProbe notifications in Settings first.") }
            Section("2 · ArcProbe notification arrives") { Text("On iOS 27, create a Notification automation for ArcProbe, filtered to title ‘ArcProbe tracking pulse’. Run Process Tracking Notification and pass the trigger’s Message/body into Notification Message. This single action fetches recent data and schedules the next pulse. Do not add a Repeat or Wait action.") }
            Section("3 · Arcaea closes") { Text("Run Stop Notification Tracking. A Focus-off automation may be used experimentally if it matches your gaming setup; Game Mode and Focus are different controls.") }
            Section("Delivery") { Text("Use immediate notification delivery and allow ArcProbe through the Focus used while playing. If a pulse does not trigger the automation, the chain stops; start tracking again. Physical iOS 27 testing is still required. On iOS 18 use the existing generation-based Repeat/Wait recipe.") }
        }.navigationTitle("Notification setup")
    }
}
