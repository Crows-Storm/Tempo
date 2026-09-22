import ServiceManagement
import AppKit
import SwiftUI

struct MenuBarPanel: View {
    var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                Text(PhaseCopy.title(model.clock.phase))
                    .font(.headline)
                TimerReadout(seconds: model.remaining(at: context.date), phase: model.clock.phase, compact: true)
                HStack {
                    Button(model.clock.runState == .running ? "Pause" : "Start") { model.toggle() }
                        .buttonStyle(.borderedProminent)
                        .tint(TempoColor.phase(model.clock.phase))
                    Button("Stop") { model.stop() }
                        .disabled(model.clock.runState == .idle)
                }
                Button("Open") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
                    model.section = .focus
                }
            }
            .padding(TempoSpacing.md)
            .frame(width: 220)
            .onChange(of: context.date) { _, date in
                model.reconcile(now: date)
            }
        }
    }
}

struct WelcomeSheet: View {
    var start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack(alignment: .center, spacing: TempoSpacing.md) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text("Tempo")
                    .font(.largeTitle)
            }
            Text("Tempo is a focus timer, a task board, and a private history of your work.")
                .fixedSize(horizontal: false, vertical: true)
            Text("This data stays on this Mac.")
                .foregroundStyle(TempoColor.secondary)
            HStack {
                Spacer()
                Button("Continue") { start() }
                    .buttonStyle(.borderedProminent)
                    .tint(TempoColor.info)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(TempoSpacing.lg)
        .frame(width: 440)
    }
}
