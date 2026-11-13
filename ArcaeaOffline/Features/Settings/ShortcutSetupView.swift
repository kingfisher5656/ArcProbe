import SwiftUI

/// How to wire ArcProbe to Arcaea with two personal automations in the Shortcuts app.
struct ShortcutSetupView: View {
    var body: some View {
        List {
            Section {
                Text("ArcProbe cannot see Arcaea by itself. Two automations in the Shortcuts app tell it when Arcaea opens and closes, and a small loop asks ArcProbe to check for new plays.")
            }
            Section("1 · Shortcut “ArcProbe tracking”") {
                step(1, "Start Arcaea Tracking")
                step(2, "Repeat 1000 times")
                step(3, "Check Recent Play — set Session to the result of step 1", indent: true)
                step(4, "If Check Recent Play is less than 1 → Stop This Shortcut → End If", indent: true)
                step(5, "Wait — set the duration to the result of Check Recent Play", indent: true)
                step(6, "End Repeat")
            }
            Section("2 · Automations") {
                Label("When Arcaea is opened → run “ArcProbe tracking”", systemImage: "play.circle")
                Label("When Arcaea is closed → Stop Arcaea Tracking", systemImage: "stop.circle")
                Text("Set both to Run Immediately and turn off Notify When Run.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("How it behaves") {
                Text("ArcProbe decides the timing: it checks about every 65–80 seconds and returns the number of seconds to wait.")
                Text("Closing and reopening Arcaea quickly is fine. The newest loop takes over, older loops end at their next check, and the timing carries on without starting over.")
                Text("After Arcaea closes, the loop makes two more checks and then ends.")
                Text("If the tracker account must sign in again, the shortcut stops with a message and Settings shows a warning.")
            }
            Section {
                NavigationLink("Notification method (experimental)") { NotificationMethodView() }
            } footer: {
                Text("Only for systems that stop long-running automations after a few minutes.")
            }
        }
        .navigationTitle("Shortcut setup").navigationBarTitleDisplayMode(.inline)
    }
    private func step(_ number: Int, _ text: String, indent: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)").font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary)
            Text(text)
        }.padding(.leading, indent ? 22 : 0)
    }
}

private struct NotificationMethodView: View {
    @Environment(ArchiveModel.self) private var model
    @State private var allowed: Bool?
    var body: some View {
        List {
            Section {
                Text("Instead of one shortcut that waits between checks, ArcProbe posts a silent notification for each check, and a Notification automation runs it. This has not been verified on a real device yet. Use either this or the Repeat loop, never both.")
            }
            Section("Notifications") {
                LabeledContent("Permission", value: allowed == nil ? "Checking…" : allowed == true ? "Allowed" : "Not allowed")
                if allowed == false {
                    Button("Allow notifications") {
                        Task {
                            do { allowed = try await NotificationTracking.shared.requestPermission() }
                            catch { model.errorMessage = error.localizedDescription }
                        }
                    }
                }
            }
            Section("Automations") {
                Label("When Arcaea is opened → Start Notification Tracking", systemImage: "play.circle")
                Label("When ArcProbe sends a notification titled “\(NotificationTracking.title)” → Process Tracking Notification, with Notification Message set to the notification’s message", systemImage: "bell")
                Label("When Arcaea is closed → Stop Arcaea Tracking", systemImage: "stop.circle")
                Text("Let ArcProbe notifications through the Focus you play in, with immediate delivery.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Notification method").navigationBarTitleDisplayMode(.inline)
        .task { allowed = await NotificationTracking.shared.authorized() }
    }
}
