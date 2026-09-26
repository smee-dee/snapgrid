#if os(macOS)
import AppKit
import ApplicationServices
import Carbon
import SnapgridCore
import ServiceManagement
import SwiftUI

let reloadNotification = Notification.Name("dev.snapgrid.reload")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configURL: URL
    private var config: Config?
    private var configError: String?
    private var globalIDs: [UInt32] = []
    private var localIDs: [UInt32] = []
    private var leaderID: UInt32?
    private var leaderTimeout: DispatchWorkItem?
    private var failedCombos: [String] = []
    private var layoutTable: [UInt32: Character] = [:]
    private var statusItem: NSStatusItem!
    private var watcher: DispatchSourceFileSystemObject?
    private var lastConfigText: String?
    private var settingsModel: SettingsModel?
    private var settingsWindow: NSWindow?

    init(configURL: URL) {
        self.configURL = configURL
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon(armed: false)
        installMainMenu()

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            log("Accessibility permission missing — grant it in System Settings › Privacy & Security › Accessibility")
        }

        let firstRun = !FileManager.default.fileExists(atPath: configURL.path)
        if firstRun { try? CLI.writeDefaultConfig(to: configURL, force: false) }
        reload()
        watchConfigDirectory()
        if firstRun { showSettings() }
        DistributedNotificationCenter.default().addObserver(
            forName: reloadNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.registerHotKeys() }
        }
    }

    // MARK: Config

    @objc func reload() {
        do {
            let text = try String(contentsOf: configURL, encoding: .utf8)
            let parsed = try Config.parse(text)
            config = parsed
            configError = nil
            lastConfigText = text
            parsed.warnings.forEach { log("warning: \($0)") }
            log("loaded \(parsed.shortcuts.count) shortcuts from \(configURL.path)")
        } catch {
            // Keep the previous working config active so a typo doesn't disable everything.
            configError = "\(error)"
            log("config error: \(error)")
        }
        registerHotKeys()
    }

    private func watchConfigDirectory() {
        let dir = configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        var pending: DispatchWorkItem?
        source.setEventHandler { [weak self] in
            pending?.cancel()
            let work = DispatchWorkItem {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let text = try? String(contentsOf: self.configURL, encoding: .utf8)
                    if text != nil, text != self.lastConfigText { self.reload() }
                }
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    // MARK: Hotkeys

    private func unregisterHotKeys() {
        disarmLeader()
        HotKeyCenter.shared.unregisterAll(globalIDs)
        globalIDs = []
        if let leaderID { HotKeyCenter.shared.unregister(leaderID) }
        leaderID = nil
    }

    private func registerHotKeys() {
        unregisterHotKeys()
        failedCombos = []
        layoutTable = KeyboardLayout.characterTable()
        defer { settingsModel?.notRegistered = failedCombos }

        guard let config else { rebuildMenu(); return }
        for shortcut in config.shortcuts where shortcut.global {
            if let id = register(shortcut.combo, { [weak self] in self?.run(shortcut) }) {
                globalIDs.append(id)
            }
        }
        if let leader = config.settings.leader, config.shortcuts.contains(where: { !$0.global }) {
            leaderID = register(leader) { [weak self] in self?.armLeader() }
        }
        rebuildMenu()
    }

    private func register(_ combo: KeyCombo, _ handler: @escaping () -> Void) -> UInt32? {
        guard let code = KeyboardLayout.resolve(combo.key, table: layoutTable) else {
            failedCombos.append("\(combo) (key not on this keyboard layout)")
            log("cannot resolve key for \(combo)")
            return nil
        }
        guard let id = HotKeyCenter.shared.register(keyCode: code, modifiers: combo.modifiers, handler: handler) else {
            failedCombos.append("\(combo) (already in use)")
            log("cannot register \(combo): already used by macOS or another app")
            return nil
        }
        return id
    }

    /// Local shortcuts are only registered for a few seconds after the leader key,
    /// mirroring Divvy's local shortcuts that work while its panel is open.
    private func armLeader() {
        guard let config else { return }
        disarmLeader()
        for shortcut in config.shortcuts where !shortcut.global {
            if let id = register(shortcut.combo, { [weak self] in
                self?.disarmLeader()
                self?.run(shortcut)
            }) { localIDs.append(id) }
        }
        if !config.shortcuts.contains(where: { !$0.global && $0.combo == KeyCombo(modifiers: [], key: .code(53)) }),
           let id = register(KeyCombo(modifiers: [], key: .code(53)), { [weak self] in self?.disarmLeader() }) {
            localIDs.append(id)
        }
        setIcon(armed: true)
        let timeout = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.disarmLeader() } }
        leaderTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + config.settings.leaderTimeout, execute: timeout)
    }

    private func disarmLeader() {
        leaderTimeout?.cancel()
        leaderTimeout = nil
        HotKeyCenter.shared.unregisterAll(localIDs)
        localIDs = []
        if statusItem != nil { setIcon(armed: false) }
    }

    private func run(_ shortcut: Shortcut) {
        do {
            try WindowMover.perform(shortcut.action, gap: config?.settings.gap ?? 0)
        } catch WindowMoverError.notTrusted {
            NSSound.beep()
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        } catch {
            NSSound.beep()
            log("\(shortcut.name): \(error)")
        }
    }

    // MARK: Menu

    private func setIcon(armed: Bool) {
        let name = armed ? "square.grid.3x3.fill" : "square.grid.3x3"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Snapgrid")
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        func info(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if let config {
            let local = config.shortcuts.filter { !$0.global }.count
            info("Snapgrid — \(config.shortcuts.count - local) global, \(local) local shortcuts")
            if let leader = config.settings.leader, local > 0 { info("Leader: \(leader)") }
        } else {
            info("Snapgrid — no config loaded")
        }
        if let configError { info("⚠︎ Config error: \(configError)") }
        for failed in failedCombos { info("⚠︎ Not registered: \(failed)") }
        if !AXIsProcessTrusted() {
            menu.addItem(NSMenuItem(title: "⚠︎ Grant Accessibility Permission…", action: #selector(openAccessibility), keyEquivalent: ""))
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Reload Config", action: #selector(reload), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Edit Config File", action: #selector(openConfig), keyEquivalent: "e"))
        menu.addItem(NSMenuItem(title: "Show Config in Finder", action: #selector(revealConfig), keyEquivalent: ""))
        if Bundle.main.bundleURL.pathExtension == "app" {
            let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(login)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Snapgrid", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != nil && item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        statusItem.menu = menu
    }

    @objc private func openConfig() {
        if !FileManager.default.fileExists(atPath: configURL.path) {
            try? CLI.writeDefaultConfig(to: configURL, force: false)
        }
        NSWorkspace.shared.open(configURL)
    }

    @objc private func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([configURL])
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            log("launch at login: \(error.localizedDescription)")
        }
        rebuildMenu()
    }

    // MARK: Settings window

    @objc func showSettings() {
        let model = settingsModel ?? makeSettingsModel()
        if let settingsWindow {
            if !model.isDirty { model.revert() }
            if !settingsWindow.isVisible { settingsWindow.center() }
        } else {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "Snapgrid Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 860, height: 620))
            window.center()
            settingsWindow = window
        }
        model.notRegistered = failedCombos
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsModel() -> SettingsModel {
        let model = SettingsModel(configURL: configURL)
        model.onSave = { [weak self] in self?.reload() }
        model.pauseHotKeys = { [weak self] paused in
            if paused { self?.unregisterHotKeys() } else { self?.registerHotKeys() }
        }
        model.onLoginChanged = { [weak self] in self?.rebuildMenu() }
        settingsModel = model
        return model
    }

    /// Opening the app again (Finder, Spotlight) while it runs shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    /// A menu-bar app has no main menu by default, which leaves ⌘C/⌘V/⌘W dead in the Settings window.
    private func installMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit Snapgrid", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let main = NSMenu()
        for submenu in [appMenu, edit] {
            let item = NSMenuItem()
            item.submenu = submenu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        settingsModel?.stopRecording()
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("snapgrid: \(message)\n".utf8))
}
#endif
