import AppKit
import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case focus
    case tasks
    case appearance
    case language
    case notifications
    case data
    case about

    var id: Self { self }

    var titleKey: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .focus: "Focus"
        case .tasks: "Tasks"
        case .appearance: "Appearance"
        case .language: "Language"
        case .notifications: "Notifications"
        case .data: "Data"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .focus: "timer"
        case .tasks: "checklist"
        case .appearance: "circle.lefthalf.filled"
        case .language: "globe"
        case .notifications: "bell"
        case .data: "internaldrive"
        case .about: "info.circle"
        }
    }
}

@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var selectedTab: SettingsTab? = .general
    private init() {}
}

struct SettingsRoot: View {
    @Bindable var model: AppModel
    @State private var navigation = SettingsNavigation.shared
    @State private var navigationHistory: [SettingsTab] = [.general]
    @State private var historyIndex = 0
    @State private var isHistoryNavigation = false

    private var activeTab: SettingsTab {
        navigation.selectedTab ?? .general
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $navigation.selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.titleKey, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .listStyle(.sidebar)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 200)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            SettingsDetailView(model: model, tab: activeTab)
        }
        .navigationTitle("Settings")
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 660, minHeight: 480)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canGoBack)
                Button {
                    goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!canGoForward)
            }
        }
        .onChange(of: navigation.selectedTab) { _, _ in
            recordNavigation()
        }
    }

    private var canGoBack: Bool { historyIndex > 0 }
    private var canGoForward: Bool { historyIndex < navigationHistory.count - 1 }

    private func goBack() {
        guard canGoBack else { return }
        isHistoryNavigation = true
        historyIndex -= 1
        navigation.selectedTab = navigationHistory[historyIndex]
        DispatchQueue.main.async { isHistoryNavigation = false }
    }

    private func goForward() {
        guard canGoForward else { return }
        isHistoryNavigation = true
        historyIndex += 1
        navigation.selectedTab = navigationHistory[historyIndex]
        DispatchQueue.main.async { isHistoryNavigation = false }
    }

    private func recordNavigation() {
        guard !isHistoryNavigation, let tab = navigation.selectedTab else { return }
        if navigationHistory[historyIndex] == tab { return }
        if historyIndex < navigationHistory.count - 1 {
            navigationHistory = Array(navigationHistory.prefix(historyIndex + 1))
        }
        navigationHistory.append(tab)
        historyIndex = navigationHistory.count - 1
    }
}

private struct SettingsDetailView: View {
    @Bindable var model: AppModel
    var tab: SettingsTab

    var body: some View {
        Group {
            switch tab {
            case .general: GeneralPane(model: model)
            case .focus: FocusPane(model: model)
            case .tasks: TasksPane(model: model)
            case .appearance: AppearancePane(model: model)
            case .language: LanguagePane(model: model)
            case .notifications: NotificationsPane(model: model)
            case .data: DataPane(model: model)
            case .about: AboutPane()
            }
        }
        .navigationTitle(tab.titleKey)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private extension View {
    func settingsPaneChrome() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
    }
}

private struct GeneralPane: View {
    @Bindable var model: AppModel
    @State private var launch = SMLaunch.current
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("System") {
                Toggle(isOn: $launch) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at login")
                        Text("Open Tempo when you sign in to this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: launch) { _, enabled in
                    launchError = SMLaunch.set(enabled)
                }
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .settingsPaneChrome()
    }
}

private enum SMLaunch {
    static var current: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

private struct FocusPane: View {
    @Bindable var model: AppModel
    @State private var accessibilityOn = false

    var body: some View {
        Form {
            Section("Focus") {
                durationSlider("Focus length", value: $model.settings.focusMinutes, marks: DurationMarks.focus)
                durationSlider("Short break length", value: $model.settings.shortBreakMinutes, marks: DurationMarks.shortBreak)
                durationSlider("Long break length", value: $model.settings.longBreakMinutes, marks: DurationMarks.longBreak)
                durationSlider(
                    "Sessions before a long break",
                    value: $model.settings.longBreakInterval,
                    marks: DurationMarks.sessions,
                    showsMinutes: false
                )
            }
            Section("Activity") {
                LabeledContent("Sample interval") {
                    Stepper(value: $model.settings.monitorInterval, in: 1...60, step: 1) {
                        Text(Duration.seconds(model.settings.monitorInterval).formatted(.units(allowed: [.seconds], width: .wide)))
                    }
                }
                LabeledContent("Window titles") {
                    if accessibilityOn {
                        Text("On")
                    } else {
                        Button(model.settings.askedAccessibility ? "Open System Settings" : "Enable") {
                            model.enableAccessibilityFromSettings()
                        }
                    }
                }
                Text("App names still record without this. Window titles need Accessibility. Tempo asks once when you start a focus; after a refusal, use this button.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Suggest a board when a focus ends without one", isOn: $model.settings.suggestBoard)
                    .toggleStyle(.switch)
            }
            Section("Distraction list") {
                ForEach(model.settings.distractionRules) { rule in
                    HStack {
                        TextField("App", text: Binding(
                            get: { rule.app },
                            set: { model.updateDistractionRule(rule.id, app: $0) }
                        ))
                        TextField("Title", text: Binding(
                            get: { rule.title },
                            set: { model.updateDistractionRule(rule.id, title: $0) }
                        ))
                        Button("Remove", role: .destructive) {
                            model.removeDistractionRule(rule.id)
                        }
                        .controlSize(.small)
                    }
                }
                Button("Add") {
                    model.addDistractionRule()
                }
                .controlSize(.small)
                Text("Efficiency is the share of samples that did not match your distraction list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .settingsPaneChrome()
        .task { accessibilityOn = FrontmostProbe.isTrusted }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityOn = FrontmostProbe.isTrusted
        }
    }

    private func durationSlider(
        _ title: LocalizedStringResource,
        value: Binding<Int>,
        marks: [Int],
        showsMinutes: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
            HStack {
                Text(title)
                Spacer()
                Text(readout(value.wrappedValue, showsMinutes: showsMinutes))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            MarkedSlider(
                value: value,
                marks: marks,
                accessibilityTitle: String(localized: title)
            )
            .frame(minHeight: 22)
            HStack(spacing: 0) {
                ForEach(marks, id: \.self) { mark in
                    Text("\(mark)")
                        .font(.caption2)
                        .foregroundStyle(mark == value.wrappedValue ? TempoColor.label : TempoColor.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func readout(_ value: Int, showsMinutes: Bool) -> String {
        if showsMinutes {
            return Duration.seconds(value * 60).formatted(.units(allowed: [.minutes], width: .abbreviated))
        }
        return "\(value)"
    }
}

private struct TasksPane: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Tasks") {
                Toggle("Confirm before deleting a card", isOn: $model.settings.confirmDeleteCard)
                    .toggleStyle(.switch)
            }
        }
        .settingsPaneChrome()
    }
}

private struct AppearancePane: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $model.settings.appearance) {
                    ForEach(AppearanceChoice.allCases) { choice in
                        Text(choice.titleKey).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .settingsPaneChrome()
    }
}

private struct LanguagePane: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Language") {
                Picker("Language", selection: $model.settings.language) {
                    Text("Follow System").tag(LanguagePreference.system)
                    Text("English").tag(LanguagePreference.en)
                    Text("Simplified Chinese").tag(LanguagePreference.zhHans)
                    Text("Japanese").tag(LanguagePreference.ja)
                }
                .pickerStyle(.menu)
                .onChange(of: model.settings.language) { _, language in
                    language.apply()
                }
                Text("Quit and reopen Tempo to finish changing the language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .settingsPaneChrome()
    }
}

private struct NotificationsPane: View {
    @Bindable var model: AppModel
    @State private var granted = false

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Notify when a session ends", isOn: $model.settings.notificationsEnabled)
                    .toggleStyle(.switch)
                Toggle("Play a sound when a session ends", isOn: $model.settings.soundEnabled)
                    .toggleStyle(.switch)
                if model.settings.notificationsEnabled, !granted {
                    Button(model.settings.askedNotifications ? "Open System Settings" : "Enable") {
                        model.enableNotificationsFromSettings()
                    }
                    Text("Tempo asks once when a session ends. After a refusal, use this button to open System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .settingsPaneChrome()
        .task { granted = await SessionNotifier.isGranted() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { granted = await SessionNotifier.isGranted() }
        }
    }
}

private struct DataPane: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Data") {
                Text("Tempo keeps focus, tasks, and history on this Mac. There is no account and nothing is uploaded.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Import") { model.importJSON() }
                        .controlSize(.small)
                    Button("Export") { model.exportJSON() }
                        .controlSize(.small)
                }
                Button("Import previous Pomodoro Logger data") {
                    Task { await model.importLegacyIfNeeded(force: true) }
                }
                .controlSize(.small)
            }
            Section {
                Button("Clear All Data", role: .destructive) { model.showClearConfirm = true }
            }
        }
        .settingsPaneChrome()
        .alert("Clear all focus data on this Mac?", isPresented: $model.showClearConfirm) {
            Button("Clear", role: .destructive) { model.clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}

private struct AboutPane: View {
    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tempo")
                            .font(.title2)
                        Text(versionText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("About") {
                Text("Tempo keeps focus, tasks, and history on this Mac. There is no account and nothing is uploaded.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .settingsPaneChrome()
    }

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return String(localized: "Version \(version) (\(build))")
    }
}
