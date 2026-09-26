#if os(macOS)
import AppKit
import ApplicationServices
import ServiceManagement
import SnapgridCore
import SwiftUI

enum LoginItem {
    static var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

enum Accessibility {
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Adds Snapgrid to the Accessibility list (with the system prompt) and opens that pane.
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable { case welcome, accessibility, shortcuts, finish }
    enum Source: Hashable { case keep, iCloud, divvy, example }

    static let completedKey = "onboardingCompleted"

    @Published var step: Step = .welcome
    @Published var source: Source
    @Published var syncWithICloud: Bool
    @Published private(set) var accessibilityGranted = Accessibility.isGranted
    @Published var error: String?
    @Published private(set) var summary = ""

    let configURL: URL
    let cloud = CloudSync.iCloudDrive
    /// Shortcut counts for the available sources; nil when that source isn't there.
    let currentCount: Int?
    let divvyCount: Int?
    let cloudCount: Int?
    var onApply: () -> Config? = { nil }
    var onFinish: (_ openSettings: Bool) -> Void = { _ in }

    init(configURL: URL, currentConfig: Config?) {
        self.configURL = configURL
        currentCount = currentConfig?.shortcuts.count
        divvyCount = (try? Self.divvyConfig())?.shortcuts.count
        let cloud = CloudSync.iCloudDrive
        cloudCount = cloud.hasCloudConfig ? (try? Config.load(from: cloud.configURL))?.shortcuts.count : nil
        syncWithICloud = cloud.isEnabled(for: configURL)
        if currentCount != nil { source = .keep }
        else if cloudCount != nil { source = .iCloud }
        else if divvyCount != nil { source = .divvy }
        else { source = .example }
    }

    static func divvyConfig() throws -> Config {
        let (data, source) = try CLI.readInstalledDivvyPreferences()
        let table = KeyboardLayout.characterTable()
        let text = DivvyImporter.renderConfig(try DivvyImporter.readPreferences(data), source: source,
                                              layoutCharacter: { table[$0] })
        return try Config.parse(text)
    }

    func refreshStatus() {
        let granted = Accessibility.isGranted
        if granted != accessibilityGranted { accessibilityGranted = granted }
    }

    func back() {
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    func next() {
        if step == .shortcuts, !applyShortcuts() { return }
        if let following = Step(rawValue: step.rawValue + 1) { step = following }
    }

    private func applyShortcuts() -> Bool {
        do {
            switch source {
            case .keep: break
            case .example: try CLI.writeDefaultConfig(to: configURL, force: true)
            case .divvy: try CLI.write(try Self.divvyConfig().render(), to: configURL, force: true)
            case .iCloud: try cloud.enable(for: configURL, useCloudCopy: true)
            }
            if syncWithICloud, !cloud.isEnabled(for: configURL) {
                try cloud.enable(for: configURL, useCloudCopy: false)
            } else if !syncWithICloud, source != .iCloud {
                try cloud.disable(for: configURL)
            }
        } catch {
            self.error = (error as? CLI.Failure)?.message ?? "\(error)"
            return false
        }
        if let config = onApply() {
            let local = config.shortcuts.filter { !$0.global }.count
            summary = "\(config.shortcuts.count) shortcuts are ready."
            if let leader = config.settings.leader, local > 0 {
                summary += " For the \(local) that work after the leader key, press \(leader.symbols), then the key."
            }
        } else {
            summary = "Your config has an error. Open Settings to fix it."
        }
        return true
    }

    var launchAtLogin: Bool {
        get { LoginItem.isEnabled }
        set {
            objectWillChange.send()
            do { try LoginItem.set(newValue) } catch { self.error = "Launch at login: \(error.localizedDescription)" }
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case .welcome: welcome
                case .accessibility: accessibility
                case .shortcuts: shortcuts
                case .finish: finish
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(28)
            Divider()
            footer.padding(16)
        }
        .frame(width: 580, height: 480)
        .alert("Snapgrid", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error ?? "")
        }
        .task {
            while !Task.isCancelled {
                model.refreshStatus()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func header(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(Color.accentColor)
            Text(title).font(.title).bold()
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
    }

    private var welcome: some View {
        header("square.grid.3x3", "Welcome to Snapgrid",
               "Snapgrid places windows on a grid with keyboard shortcuts, like Divvy. Setup takes about a minute: allow window control, choose your shortcuts, done.")
    }

    private var accessibility: some View {
        VStack(spacing: 16) {
            header("hand.raised", "Allow Snapgrid to move windows",
                   "macOS only lets apps move other apps' windows with Accessibility permission. Click the button, then turn on Snapgrid in the list.")
            if model.accessibilityGranted {
                Label("Permission granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.headline)
            } else {
                Button("Open Accessibility Settings") { Accessibility.request() }.controlSize(.large)
                Text("This page updates by itself once it's on.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose your shortcuts").font(.title2).bold().frame(maxWidth: .infinity)
                .padding(.bottom, 6)
            if let n = model.currentCount {
                choice(.keep, "Keep my current settings", "\(n) shortcuts in \((model.configURL.path as NSString).abbreviatingWithTildeInPath)")
            }
            if let n = model.cloudCount {
                choice(.iCloud, "Use my settings from iCloud Drive", "\(n) shortcuts saved by Snapgrid on another Mac")
            }
            if let n = model.divvyCount {
                choice(.divvy, "Import from Divvy", "\(n) shortcuts found in Divvy's settings")
            }
            choice(.example, "Start with example shortcuts", "Halves, thirds and moving between displays. Easy to change later.")
            Divider().padding(.vertical, 6)
            Toggle(isOn: Binding(get: { model.syncWithICloud || model.source == .iCloud },
                                 set: { model.syncWithICloud = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync settings with iCloud Drive")
                    Text(model.cloud.isAvailable
                         ? (model.cloudCount != nil && model.source != .iCloud
                            ? "Replaces the settings in iCloud Drive with this choice (a backup is kept)."
                            : "Your other Macs with Snapgrid can use the same shortcuts.")
                         : "iCloud Drive is off on this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(!model.cloud.isAvailable || model.source == .iCloud)
            Spacer()
            Text("You can import from Divvy or change any of this later in Settings.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func choice(_ source: OnboardingModel.Source, _ title: String, _ detail: String) -> some View {
        Button { model.source = source } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: model.source == source ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(model.source == source ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var finish: some View {
        VStack(spacing: 16) {
            header("checkmark.seal", "You're ready", model.summary)
            if LoginItem.isAvailable {
                Toggle("Start Snapgrid when I log in", isOn: $model.launchAtLogin)
            }
            if !model.accessibilityGranted {
                Label("Accessibility permission is still missing, so shortcuts can't move windows yet.",
                      systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Text("Snapgrid lives in the menu bar (\(Image(systemName: "square.grid.3x3"))). Open Settings there anytime.")
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(OnboardingModel.Step.allCases, id: \.self) { step in
                    Circle().fill(step == model.step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            if model.step != .welcome, model.step != .finish {
                Button("Back") { model.back() }
            }
            switch model.step {
            case .welcome:
                Button("Get Started") { model.next() }.keyboardShortcut(.defaultAction)
            case .accessibility:
                Button(model.accessibilityGranted ? "Continue" : "Skip for Now") { model.next() }
                    .keyboardShortcut(.defaultAction)
            case .shortcuts:
                Button("Continue") { model.next() }.keyboardShortcut(.defaultAction)
            case .finish:
                Button("Open Settings") { model.onFinish(true) }
                Button("Done") { model.onFinish(false) }.keyboardShortcut(.defaultAction)
            }
        }
    }
}
#endif
