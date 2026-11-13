import AppKit
import CoreGraphics
import Darwin
import SwiftUI
import UserNotifications

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, OperationNotificationHandler {
    private var app = NSApplication.shared
    private(set) var model = AppModel()
    private let operationNotifications = OperationNotifications()
    private var quietLaunch = false
    private var screenParametersObserver: NSObjectProtocol?
    private var constrainingSettings = false
    private var settingsAutosaveName: String {
        MultiAuditEnvironment.windowAutosaveName("MultiShift.SettingsWindow")
    }
    private var statusItem: NSStatusItem?
    private var dragPanel: NSPanel?
    private var welcomeWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var chooserWindow: NSWindow?
    private var operationWindow: NSWindow?
    private var managedWindows: [ObjectIdentifier: NSWindow] = [:]
    private var inputTimer: Timer?
    private var wheelActivity: NSObjectProtocol?
    private var wheelGeometry = WheelGeometry()
    private var wheelInteraction = WheelInteractionState()
    private var wheelFiles: [URL] = []
    private var dragPasteboardChange = -1
    private var commandQMonitor: Any?
    private var appearanceSubscription: Any?
    private var accessibilityOptionsObserver: NSObjectProtocol?
    private var systemAppearanceObservation: NSKeyValueObservation?
    private var downAt: NSPoint?
    private var triggerFired = false
    private var shiftWasDown = false
    private var lastFiles: [URL] = []
    private var pendingOpenFiles: [URL] = []

    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            Darwin.exit(nativeSelfTest())
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        delegate.quietLaunch = CommandLine.arguments.contains("--quiet")
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }

    private static func nativeSelfTest() -> Int32 {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let contents = executable.deletingLastPathComponent().deletingLastPathComponent()
        let appURL = contents.deletingLastPathComponent()
        let infoURL = contents.appendingPathComponent("Info.plist")
        let pkgInfoURL = contents.appendingPathComponent("PkgInfo")
        let helper = contents.appendingPathComponent("Resources/MultiShiftEngine/MultiShiftEngine")
        guard let infoData = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == AppModel.bundleID,
              info["CFBundleExecutable"] as? String == "MultiShift",
              info["CFBundlePackageType"] as? String == "APPL",
              let version = info["CFBundleShortVersionString"] as? String,
              let buildNumber = info["CFBundleVersion"] as? String,
              buildNumber.range(of: "^[1-9][0-9]{0,8}$", options: .regularExpression) != nil,
              info["MultiShiftEngineVersion"] as? String == version,
              let buildID = info["MultiShiftBuildID"] as? String, !buildID.isEmpty,
              let sourceFingerprint = info["MultiShiftSourceFingerprint"] as? String, !sourceFingerprint.isEmpty,
              let pkgInfo = try? Data(contentsOf: pkgInfoURL),
              String(data: pkgInfo.prefix(4), encoding: .ascii) == "APPL",
              FileManager.default.isExecutableFile(atPath: executable.path),
              FileManager.default.isExecutableFile(atPath: helper.path),
              Bundle(url: appURL) != nil else {
            fputs("NATIVE SELFTEST FAILED: bundle structure is incomplete\n", stderr)
            return 1
        }
        do {
            let response = try EngineClient().execute(executable: helper, request: [
                "request_id": UUID().uuidString, "operation": "version"
            ])
            guard response["engine_version"] as? String == version else {
                fputs("NATIVE SELFTEST FAILED: app and engine versions differ\n", stderr)
                return 1
            }
            let engine = contents.appendingPathComponent("Resources/MultiShiftEngine")
            let buildInfoURL = contents.appendingPathComponent("Resources/BUILD.json")
            guard let buildInfoData = try? Data(contentsOf: buildInfoURL),
                  let buildInfo = try? JSONSerialization.jsonObject(with: buildInfoData) as? [String: String],
                  buildInfo["build_number"] == buildNumber,
                  buildInfo["build_id"] == buildID,
                  buildInfo["source_fingerprint"] == sourceFingerprint else {
                fputs("NATIVE SELFTEST FAILED: build fingerprint is inconsistent\n", stderr)
                return 1
            }
            let nested = (FileManager.default.enumerator(at: engine, includingPropertiesForKeys: [.isExecutableKey])?.allObjects as? [URL]) ?? []
            guard nested.contains(where: { (try? $0.resourceValues(forKeys: [.isExecutableKey]).isExecutable) == true }) else {
                fputs("NATIVE SELFTEST FAILED: packaged engine has no executable payload\n", stderr)
                return 1
            }
            print("NATIVE SELFTEST OK · \(version) · \(buildID)")
            return 0
        } catch {
            fputs("NATIVE SELFTEST FAILED: engine protocol check failed\n", stderr)
            return 1
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let directory = ProcessInfo.processInfo.environment["MULTI_ECOSYSTEM_REVIEW"] {
            NSLog("LAYOUT REVIEW launch: %@", directory)
            app.setActivationPolicy(.regular)
            model.delegate = self
            installStatusItem(); observeAppearance()
            if ProcessInfo.processInfo.environment["MULTI_AUDIT_SCENARIO"] == "circle" {
                runCircleAudit(directory: directory)
                return
            }
            if let action = ProcessInfo.processInfo.environment["MULTISHIFT_FEATURE_REVIEW"] {
                model.appearance = ProcessInfo.processInfo.environment["MULTISHIFT_REVIEW_THEME"] ?? "light"
                let fixtureName = ProcessInfo.processInfo.environment["MULTISHIFT_REVIEW_FIXTURE"] ?? "fixture.png"
                let fixture = URL(fileURLWithPath: directory).appendingPathComponent(URL(fileURLWithPath: fixtureName).lastPathComponent)
                if action == "order" {
                    confirmCombination(files: [fixture, fixture.deletingLastPathComponent().appendingPathComponent("second.png")],
                                       action: ActionItem(id: "convert:PDF", title: "PDF", shortTitle: "PDF", hint: "", symbol: "doc"))
                } else {
                    openEditor(files: [fixture], action: ActionItem(id: "tool:" + action, title: model.text(action), shortTitle: model.text(action), hint: "", symbol: "slider.horizontal.3"))
                }
                return
            }
            if ProcessInfo.processInfo.environment["MULTI_POPOVER_ONLY"] == "1" { captureEcosystemExtras(directory: directory); return }
            showSettings()
            if ProcessInfo.processInfo.environment["MULTI_AUDIT_SCENARIO"] == "native-feedback" {
                MultiNativeStyleAudit.write(to: URL(fileURLWithPath: directory))
                operationNotifications.handler = self
                operationNotifications.install()
            }
            NSLog("LAYOUT REVIEW settings ready")
            guard let window = settingsWindow else { app.terminate(nil); return }
            if ProcessInfo.processInfo.environment["MULTI_ECOSYSTEM_INTERACTIVE"] == "1" {
                if ProcessInfo.processInfo.environment["MULTI_ECOSYSTEM_POPOVER"] == "1", let button = statusItem?.button {
                    toggleStatusPopover(button)
                }
                return
            }
            if let phase = ProcessInfo.processInfo.environment["MULTI_WINDOW_RESTORE_CHECK"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MultiEcosystemProbe.checkRelaunch(window: window, directory: directory, phase: phase, ideal: MultiInterfaceMetrics.shiftDefault)
                }
                return
            }
            MultiEcosystemProbe.run(window: window, app: "multishift", directory: directory,
                normal: MultiInterfaceMetrics.shiftDefault, minimum: MultiInterfaceMetrics.shiftMinimum,
                theme: { mode in self.model.appearance = mode; self.setAppearance(window) },
                completion: { self.captureEcosystemExtras(directory: directory) })
            return
        }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: AppModel.bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if MultiAuditEnvironment.root == nil, let other = others.first {
            other.activate(options: [])
            app.terminate(nil)
            return
        }
        app.setActivationPolicy(.accessory)
        FileJobCoordinator().cleanAbandonedJobs()
        model.delegate = self
        operationNotifications.handler = self
        operationNotifications.install()
        installStatusItem()
        UpdateController.shared.start()
        observeAppearance()
        systemAppearanceObservation = app.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateApplicationIcon() }
        }
        installCommandQMonitor()
        model.refreshAccessibilityDisplayOptions()
        accessibilityOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.model.refreshAccessibilityDisplayOptions() } }
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in
            self?.constrainSettingsWindow()
            self?.hideWheel()
        } }
        startInputMonitor()
        if MultiAuditEnvironment.isFunctional,
           ProcessInfo.processInfo.environment["MULTI_AUDIT_SCENARIO"] == "functional" {
            runFunctionalAudit()
            return
        }
        if CommandLine.arguments.contains("--settings") { showSettings() }
        if CommandLine.arguments.contains("--popover") {
            DispatchQueue.main.async { [weak self] in
                guard let self, let button = self.statusItem?.button else { return }
                self.toggleStatusPopover(button)
            }
        }
        // Installer handshake is restricted to a private directory in the user's temp folder.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--install-health"), index + 1 < arguments.count {
            let marker = URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL
            let directory = marker.deletingLastPathComponent()
            let temporary = URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL
            if marker.lastPathComponent == "ready",
               directory.deletingLastPathComponent() == temporary,
               directory.lastPathComponent.hasPrefix("multishift-install-"),
               (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false {
                let identity = ["version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""]
                if let data = try? JSONSerialization.data(withJSONObject: identity) {
                    try? data.write(to: marker, options: .atomic)
                }
            }
        }
        if !quietLaunch && !AppModel.defaults.bool(forKey: "welcomed") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.showWelcome() }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.hasActiveFileOperations else { return .terminateNow }
        Task { @MainActor [weak self] in
            while self?.model.hasActiveFileOperations == true {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            if AppModel.defaults.bool(forKey: "welcomed") { showSettings() } else { showWelcome() }
        }
        return true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        DispatchQueue.main.async { [weak self] in self?.showChooser(files: [URL(fileURLWithPath: filename)]) }
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        DispatchQueue.main.async { [weak self] in self?.showChooser(files: filenames.map(URL.init(fileURLWithPath:)) ) }
        sender.reply(toOpenOrPrint: .success)
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "multishift")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "multishift"
            button.setAccessibilityLabel("multishift")
            button.target = self
            button.action = #selector(toggleStatusPopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        item.menu = buildMenu()
        updateApplicationIcon()
    }

    @objc private func toggleStatusPopover(_ sender: NSStatusBarButton) {
        // NSStatusItem.menu handles both mouse buttons; this path also serves the app-menu shortcut.
        statusItem?.menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 4), in: sender)
    }
    @objc private func showStatusPopover() {
        if let button = statusItem?.button { toggleStatusPopover(button) }
    }

    private func updateApplicationIcon() {
        guard statusItem != nil || !managedWindows.isEmpty else { return }
        let dark = model.appearance == "dark" || (model.appearance == "system" && app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        if let url = Bundle.main.url(forResource: dark ? "icon-dark" : "icon-light", withExtension: "png"), let image = NSImage(contentsOf: url) {
            app.applicationIconImage = image
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "multishift")
        menu.autoenablesItems = false
        menu.delegate = self
        let state = NSMenuItem(title: model.enabled ? model.text("Pause MultiShift") : model.text("Resume MultiShift"),
                               action: #selector(toggleEnabled), keyEquivalent: "")
        state.tag = 100
        state.state = model.enabled ? .on : .off
        state.target = self
        menu.addItem(state)
        menu.addItem(.separator())
        menu.addItem(menuItem(model.text("Open files…"), #selector(openFiles)))
        if model.longRunningOperationCount > 0 {
            let processing = NSMenuItem(title: "\(model.text("Operation in progress")) · \(model.longRunningOperationCount)",
                                        action: nil, keyEquivalent: "")
            processing.tag = 101
            processing.isEnabled = false
            menu.addItem(processing)
        }
        let recent = NSMenuItem(title: model.text("Recent operations"), action: nil, keyEquivalent: "")
        let sub = NSMenu(title: recent.title)
        sub.autoenablesItems = false
        if model.recent.isEmpty {
            let empty = NSMenuItem(title: model.text("No recent operations"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            sub.addItem(empty)
        } else {
            for record in model.recent {
                let filename = record.inputNames.first ?? record.actionTitle
                let item = NSMenuItem(title: "\(record.title.lowercased()) · \(filename)", action: nil, keyEquivalent: "")
                let operationMenu = NSMenu(title: item.title)
                operationMenu.autoenablesItems = false
                item.representedObject = record.id.uuidString
                let details = menuItem(model.text("Operation details"), #selector(openRecentDetails(_:)))
                details.representedObject = record.id.uuidString
                operationMenu.addItem(details)
                let finder = menuItem(model.text("Show outputs in Finder"), #selector(showRecentInFinder(_:)))
                finder.representedObject = record.id.uuidString
                finder.isEnabled = !record.outputPaths.isEmpty
                operationMenu.addItem(finder)
                if record.canUndo {
                    let undo = menuItem(model.text("Undo"), #selector(undoRecent(_:)))
                    undo.representedObject = record.id.uuidString
                    operationMenu.addItem(undo)
                }
                item.submenu = operationMenu
                item.toolTip = record.detail
                sub.addItem(item)
            }
        }
        recent.submenu = sub
        menu.addItem(recent)
        menu.addItem(.separator())
        let settingsItem = menuItem(model.text("Settings"), #selector(showSettings))
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)
        menu.addItem(menuItem(model.text("How to use"), #selector(showWelcome)))
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: model.text("Quit MultiShift"),
                                  action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quitItem.target = app
        quitItem.keyEquivalent = "q"
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)
        return menu
    }

    private func menuItem(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        // Rebuild only at tracking boundaries; never reorder rows under the pointer.
        let snapshot = buildMenu()
        menu.removeAllItems()
        for item in snapshot.items { snapshot.removeItem(item); menu.addItem(item) }
        refreshStatusMenu()
    }

    func refreshStatusMenu() {
        statusItem?.button?.toolTip = model.enabled ? "multishift" : model.text("Pause MultiShift")
        guard let menu = statusItem?.menu else { return }
        if let state = menu.item(withTag: 100) {
            state.title = model.enabled ? model.text("Pause MultiShift") : model.text("Resume MultiShift")
            state.state = model.enabled ? .on : .off
        }
        if let processing = menu.item(withTag: 101) {
            processing.title = model.longRunningOperationCount > 0
                ? "\(model.text("Operation in progress")) · \(model.longRunningOperationCount)"
                : (model.language == "ru" ? "операции завершены" : "operations completed")
        }
        func refresh(_ menu: NSMenu) {
            for item in menu.items {
                if let raw = item.representedObject as? String, let id = UUID(uuidString: raw) {
                    let record = model.recent.first { $0.id == id }
                    item.isEnabled = record != nil
                    if item.action == #selector(showRecentInFinder(_:)) { item.isEnabled = record?.outputPaths.isEmpty == false }
                    if item.action == #selector(undoRecent(_:)) { item.isEnabled = record?.canUndo == true }
                }
                if let submenu = item.submenu { refresh(submenu) }
            }
        }
        refresh(menu)
    }

    func updateEnabled(_ enabled: Bool) {
        if model.enabled != enabled { model.enabled = enabled }
        enabledStateDidChange()
    }

    func enabledStateDidChange() {
        if !model.enabled { hideWheel() }
        startInputMonitor()
        refreshStatusMenu()
    }

    @objc private func toggleEnabled() { updateEnabled(!model.enabled) }

    @objc private func openFiles() {
        let panel = NSOpenPanel()
        setAppearance(panel)
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = model.text("Open")
        panel.message = model.text("Select files")
        if panel.runModal() == .OK { showChooser(files: panel.urls) }
    }

    @objc private func toggleSettingsSidebar() { NotificationCenter.default.post(name: .multiSidebarToggle, object: nil) }

    @objc private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: model.text("Settings"), size: MultiInterfaceMetrics.settingsSize(MultiInterfaceMetrics.shiftDefault, progress: AppModel.defaults.bool(forKey: "ecosystem.sidebarCollapsed") ? 0 : 1), resizable: true,
                                        autosaveName: settingsAutosaveName, root: SettingsView(model: model))
        }
        if let settingsWindow {
            if settingsWindow.titlebarAccessoryViewControllers.isEmpty {
                let accessory = MultiSidebarAccessory.install(on: settingsWindow, target: self, action: #selector(toggleSettingsSidebar))
                let title = model.text("Hide Sidebar")
                (accessory.view.subviews.first as? NSButton)?.setAccessibilityLabel(title)
                (accessory.view.subviews.first as? NSButton)?.toolTip = title
            }
            MultiWindowPolicy.configure(settingsWindow, minimum: MultiInterfaceMetrics.shiftMinimum, maximum: MultiInterfaceMetrics.shiftMaximum)
            settingsWindow.collectionBehavior = [.managed, .fullScreenNone]
            settingsWindow.tabbingMode = .disallowed
            constrainSettingsWindow()
        }
        present(settingsWindow)
        constrainSettingsWindow()
        // SwiftUI installs toolbar/window preferences while the hosting view attaches.
        // Reapply after that transaction; later resize/update callbacks keep it stable.
        DispatchQueue.main.async { [weak self] in self?.constrainSettingsWindow() }
    }

    @objc private func showWelcome() {
        if welcomeWindow == nil {
            welcomeWindow = makeWindow(title: model.text("Welcome to MultiShift"), size: NSSize(width: 600, height: 340), resizable: false,
                                       root: WelcomeView(model: model, close: { [weak self] in
                AppModel.defaults.set(true, forKey: "welcomed")
                self?.welcomeWindow?.close()
            }, settings: { [weak self] in self?.showSettings() }))
        }
        present(welcomeWindow)
    }

    @objc private func closeActiveWindow() {
        let window = app.keyWindow ?? app.mainWindow ?? managedWindows.values.first(where: \.isVisible)
        window?.close()
    }

    private func installApplicationMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem(title: "multishift", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "multishift")

        let settingsItem = menuItem(model.text("Settings"), #selector(showSettings))
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = .command
        appMenu.addItem(settingsItem)
        appMenu.addItem(menuItem(model.language == "ru" ? "меню multishift" : "multishift menu", #selector(showStatusPopover)))
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: model.text("Quit MultiShift"),
                                  action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = app
        quitItem.keyEquivalent = "q"
        quitItem.keyEquivalentModifierMask = .command
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileTitle = model.language == "ru" ? "файл" : "file"
        let fileMenuItem = NSMenuItem(title: fileTitle, action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: fileTitle)
        let openFilesItem = menuItem(model.text("Open files…"), #selector(openFiles))
        openFilesItem.keyEquivalent = "o"
        openFilesItem.keyEquivalentModifierMask = .command
        fileMenu.addItem(openFilesItem)
        fileMenu.addItem(.separator())
        let closeItem = menuItem(model.language == "ru" ? "закрыть окно" : "close window",
                                 #selector(closeActiveWindow))
        closeItem.keyEquivalent = "w"
        closeItem.keyEquivalentModifierMask = .command
        fileMenu.addItem(closeItem)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        editItem.submenu = editMenu; mainMenu.addItem(editItem)
        app.mainMenu = mainMenu
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow else { return }
        managedWindows.removeValue(forKey: ObjectIdentifier(closedWindow))
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let hasVisibleWindow = self.managedWindows.values.contains(where: \.isVisible)
            guard !hasVisibleWindow else { return }
            self.app.mainMenu = nil
            self.app.setActivationPolicy(.accessory)
        }
    }

    @objc private func openRecentDetails(_ sender: NSMenuItem) {
        guard let id = operationID(sender) else { return }
        showOperation(id: id)
    }

    @objc private func showRecentInFinder(_ sender: NSMenuItem) {
        guard let id = operationID(sender), let operation = model.operation(id: id) else { return }
        model.showPathsInFinder(operation.outputPaths)
    }

    @objc private func undoRecent(_ sender: NSMenuItem) {
        guard let id = operationID(sender) else { return }
        model.undoOperation(id: id)
    }

    private func operationID(_ sender: NSMenuItem) -> UUID? {
        guard let raw = sender.representedObject as? String else { return nil }
        return UUID(uuidString: raw)
    }

    func deleteHistoryEntry(id: UUID) {
        guard let operation = model.operation(id: id), operation.status != .running else { return }
        let ru = model.language == "ru"
        MultiDeletionConfirmation.request(window: operationWindow, defaults: AppModel.defaults, kind: "history",
            title: ru ? "удалить «\(operation.title)»?" : "delete ‘\(operation.title)’?",
            detail: ru ? "файлы сохранятся. откат из этой записи станет недоступен." : "files are preserved. undo from this record will no longer be available.",
            russian: ru) { [weak self] in
                guard let self else { return }
                try self.model.deleteHistoryEntry(id: id)
                self.operationWindow?.close()
            }
    }

    private func showOperation(id: UUID) {
        guard let operation = model.operation(id: id) else { return }
        let root = OperationDetailsView(model: model, operation: operation,
                                        showInFinder: { [weak self] in
            guard let operation = self?.model.operation(id: id) else { return }
            self?.model.showPathsInFinder(operation.outputPaths)
        }, undo: { [weak self] in self?.model.undoOperation(id: id) }, delete: { [weak self] in
            self?.deleteHistoryEntry(id: id)
        })
        if let operationWindow {
            operationWindow.title = operation.title.lowercased()
            operationWindow.contentView = NSHostingView(rootView: root)
        } else {
            operationWindow = makeWindow(title: operation.title.lowercased(), size: NSSize(width: 560, height: 420),
                                         resizable: false, root: root)
        }
        (operationWindow as? MultiBoundedWindow)?.onDeleteSelection = { [weak self] in self?.deleteHistoryEntry(id: id) }
        present(operationWindow)
    }

    func handleOperationNotification(id: UUID, action: String) {
        switch action {
        case UNNotificationDismissActionIdentifier: return
        case OperationNotifications.openAction:
            if let path = model.operation(id: id)?.outputPaths.first { model.openOutput(at: path) }
        case OperationNotifications.showFinderAction:
            if let operation = model.operation(id: id) { model.showPathsInFinder(operation.outputPaths) }
        case OperationNotifications.undoAction:
            model.undoOperation(id: id)
            operationNotifications.removeDeliveredOperation(id)
        default:
            showOperation(id: id)
        }
    }

    func operationDidUpdate(_ operation: RecentOperation, postNotification: Bool) {
        refreshStatusMenu()
        if postNotification && MultiAuditEnvironment.root == nil { operationNotifications.post(operation) }
    }

    func notificationPermissionChanged(_ permission: NotificationPermission) {
        model.updateNotificationPermission(permission)
    }

    func notificationDeliveryChanged(_ result: NotificationDelivery, operationID: UUID?) {
        model.updateNotificationResult(result, operationID: operationID)
    }

    func testNotification() {
        guard MultiAuditEnvironment.root == nil || ProcessInfo.processInfo.environment["MULTI_AUDIT_SCENARIO"] == "native-feedback" else { return }
        operationNotifications.testNotification()
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(AppModel.bundleID)"),
           NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    func showError(title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title.lowercased()
        alert.informativeText = interfaceCopy(detail, preserving: model.recent.flatMap { $0.inputNames + $0.outputPaths })
        alert.addButton(withTitle: model.text("Close"))
        setAppearance(alert.window)
        alert.alertStyle = .warning
        if let window = app.keyWindow { alert.beginSheetModal(for: window) }
        else { alert.runModal() }
    }

    func requestFileAccess(for file: URL, completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        setAppearance(panel)
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = model.text("Choose")
        panel.message = model.language == "ru"
            ? "выберите файл повторно, чтобы multishift смог его прочитать."
            : "choose this file again so multishift can read it."
        panel.directoryURL = file.deletingLastPathComponent()
        panel.nameFieldStringValue = file.lastPathComponent
        guard panel.runModal() == .OK, let selected = panel.url,
              selected.standardizedFileURL == file.standardizedFileURL else {
            completion(nil)
            return
        }
        completion(selected)
    }

    func requestOutputFolder(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        setAppearance(panel)
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = model.text("Choose")
        panel.message = model.language == "ru"
            ? "выберите папку для готовых результатов."
            : "choose a folder for the completed results."
        completion(panel.runModal() == .OK ? panel.url : nil)
    }

    private func captureEcosystemExtras(directory: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            app.activate(ignoringOtherApps: true)
            try? await Task.sleep(for: .milliseconds(200))
            for mode in ["light", "dark"] {
                model.appearance = mode
                if ProcessInfo.processInfo.environment["MULTI_POPOVER_ONLY"] != "1" {
                    showWelcome()
                    if let window = welcomeWindow { setAppearance(window); try? await Task.sleep(for: .milliseconds(350)); MultiEcosystemProbe.capture(window, path: directory + "/" + mode + "-welcome.png"); window.orderOut(nil) }
                }
                if ProcessInfo.processInfo.environment["MULTI_POPOVER_ONLY"] != "1" {
                    let fixture = URL(fileURLWithPath: directory).appendingPathComponent("MiXeD preview.PNG")
                    if !FileManager.default.fileExists(atPath: fixture.path) {
                        let image = NSImage(size: NSSize(width: 1200, height: 800))
                        image.lockFocus()
                        NSColor(white: 0.75, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 1200, height: 800).fill()
                        NSColor(white: 0.25, alpha: 1).setFill(); NSBezierPath(roundedRect: NSRect(x: 120, y: 120, width: 960, height: 560), xRadius: 32, yRadius: 32).fill()
                        image.unlockFocus()
                        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: fixture) }
                    }
                    let action = ActionItem(id: "tool:Resize", title: "размер", shortTitle: "размер", hint: "", symbol: "arrow.up.left.and.arrow.down.right")
                    openEditor(files: [fixture], action: action)
                    if let editor = managedWindows.values.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("MultiShift.Editor") }) {
                        for (label, size) in [("minimum", NSSize(width: 880, height: 560)), ("ideal", NSSize(width: 1000, height: 680)), ("maximum", NSSize(width: 1440, height: 900))] {
                            editor.setContentSize(size)
                            try? await Task.sleep(for: .milliseconds(450))
                            MultiEcosystemProbe.capture(editor, path: directory + "/" + mode + "-editor-" + label + ".png")
                        }
                        editor.close()
                    }
                    // A separate native viewport checks small-area reflow without
                    // weakening the editor's normal minimum on this display.
                    let small = makeWindow(title: "small-area layout review", size: NSSize(width: 700, height: 480), resizable: false,
                        root: NativeFileEditor(model: model, files: [fixture], action: action, close: {}))
                    present(small)
                    try? await Task.sleep(for: .milliseconds(450))
                    MultiEcosystemProbe.capture(small, path: directory + "/" + mode + "-editor-small-area.png")
                    small.close()
                    showChooser(files: [fixture])
                    if let chooser = chooserWindow { try? await Task.sleep(for: .milliseconds(300)); MultiEcosystemProbe.capture(chooser, path: directory + "/" + mode + "-chooser.png"); chooser.close() }
                }
                if let menu = statusItem?.menu {
                    menuWillOpen(menu)
                    let tracked = menu.items.map(ObjectIdentifier.init)
                    let enabled = model.enabled
                    model.enabled.toggle(); refreshStatusMenu()
                    let stateUpdated = menu.item(withTag: 100)?.state == (model.enabled ? .on : .off)
                    model.enabled = enabled
                    for _ in 0..<20 { refreshStatusMenu() }
                    let stable = tracked == menu.items.map(ObjectIdentifier.init)
                    let stale = NSMenuItem(title: "expired review operation", action: nil, keyEquivalent: "")
                    stale.representedObject = UUID().uuidString; menu.addItem(stale)
                    refreshStatusMenu()
                    let staleDisabled = !stale.isEnabled; menu.removeItem(stale)
                    let report: [String: Any] = ["stateUpdatedInPlace": stateUpdated,
                        "stableWhileTracking": stable, "staleOperationDisabled": staleDisabled, "nativeMenu": true, "rootItems": menu.items.count,
                        "operationCount": model.recent.count, "usesPopover": false,
                        "allOperationIDsValid": menu.items.compactMap(\.submenu).flatMap(\.items).allSatisfy { item in
                            guard let raw = item.representedObject as? String else { return true }
                            return UUID(uuidString: raw) != nil
                        }]
                    try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: directory + "/" + mode + "-native-menu.json"))
                }
            }
            app.terminate(nil)
        }
    }

    private func makeWindow<Content: View>(title: String, size: NSSize, resizable: Bool,
                                            autosaveName: String? = nil, root: Content) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = MultiBoundedWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style,
                              backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.backgroundColor = Mono.windowColor
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: root)
        // A settings animation changes the ideal size of its view tree. Let the
        // window own its size; propagating every intermediate intrinsic size to
        // AppKit can progressively enlarge it during repeated sidebar toggles.
        hostingView.sizingOptions = resizable ? [] : [.minSize]
        window.contentView = hostingView
        window.delegate = self
        window.collectionBehavior = [.managed, .fullScreenNone]
        if let autosaveName {
            if MultiAuditEnvironment.root != nil {
                if let saved = AppModel.defaults.string(forKey: "audit.settingsFrame") {
                    window.setFrame(NSRectFromString(saved), display: false)
                } else { window.center() }
            } else {
                let restored = window.setFrameUsingName(autosaveName)
                window.setFrameAutosaveName(autosaveName)
                if !restored { window.center() }
            }
        }
        window.setFrame(MultiInterfaceMetrics.visibleWindowFrame(window.frame,
            screens: NSScreen.screens.map(\.visibleFrame), minimum: .zero), display: false)
        managedWindows[ObjectIdentifier(window)] = window
        updateApplicationIcon()
        setAppearance(window)
        return window
    }

    private func setAppearance(_ window: NSWindow) {
        // AppKit owns appearance. SwiftUI inherits it from the hosting window;
        // competing preferredColorScheme overrides leave mixed native/SwiftUI chrome.
        switch model.appearance {
        case "light": app.appearance = NSAppearance(named: .aqua)
        case "dark": app.appearance = NSAppearance(named: .darkAqua)
        default: app.appearance = nil
        }
        window.appearance = nil
        window.contentView?.appearance = nil
    }

    private func constrainSettingsWindow() {
        guard let window = settingsWindow, !constrainingSettings else { return }
        constrainingSettings = true
        defer { constrainingSettings = false }
        MultiWindowPolicy.configure(window, minimum: MultiInterfaceMetrics.shiftMinimum, maximum: MultiInterfaceMetrics.shiftMaximum)
    }

    private func constrainEditorWindow(_ window: NSWindow) {
        guard !constrainingSettings else { return }
        constrainingSettings = true
        defer { constrainingSettings = false }
        MultiWindowPolicy.configure(window, minimum: NSSize(width: 880, height: 560), maximum: MultiInterfaceMetrics.editorMaximum)
    }

    func windowDidUpdate(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow { constrainSettingsWindow() }
        else if window.identifier == NSUserInterfaceItemIdentifier("MultiShift.Editor") { constrainEditorWindow(window) }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        if sender === settingsWindow {
            return MultiWindowPolicy.resizeFrameSize(sender, proposed: frameSize, minimum: MultiInterfaceMetrics.shiftMinimum, maximum: MultiInterfaceMetrics.shiftMaximum)
        }
        if sender.identifier == NSUserInterfaceItemIdentifier("MultiShift.Editor") {
            return MultiWindowPolicy.resizeFrameSize(sender, proposed: frameSize, minimum: NSSize(width: 880, height: 560), maximum: MultiInterfaceMetrics.editorMaximum)
        }
        return frameSize
    }

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        if window === settingsWindow {
            constrainSettingsWindow()
            return MultiWindowPolicy.zoomFrame(window, ideal: MultiInterfaceMetrics.shiftDefault)
        }
        if window.identifier == NSUserInterfaceItemIdentifier("MultiShift.Editor") {
            constrainEditorWindow(window)
            return MultiWindowPolicy.zoomFrame(window, ideal: NSSize(width: 1160, height: 780))
        }
        return newFrame
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow { constrainSettingsWindow() }
        else if window.identifier == NSUserInterfaceItemIdentifier("MultiShift.Editor") { constrainEditorWindow(window) }
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow {
            constrainSettingsWindow()
            saveSettingsFrame(window)
        } else if window.identifier == NSUserInterfaceItemIdentifier("MultiShift.Editor") { constrainEditorWindow(window) }
    }

    func windowDidMove(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        if let window = settingsWindow { saveSettingsFrame(window) }
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        managedWindows[ObjectIdentifier(window)] = window
        app.setActivationPolicy(.regular)
        installApplicationMenu()
        setAppearance(window)
        if window.frame.width > 0 && window.frame.height > 0 && window.isVisible {
            window.makeKeyAndOrderFront(nil)
        } else {
            if window !== settingsWindow { window.center() }
            window.makeKeyAndOrderFront(nil)
        }
        app.activate(ignoringOtherApps: true)
    }

    private func saveSettingsFrame(_ window: NSWindow) {
        if MultiAuditEnvironment.root != nil {
            AppModel.defaults.set(NSStringFromRect(window.frame), forKey: "audit.settingsFrame")
        } else { window.saveFrame(usingName: settingsAutosaveName) }
    }

    func showChooser(files: [URL]) {
        guard !files.isEmpty else { return }
        pendingOpenFiles = files
        let view = ActionChooserView(model: model, files: files) { [weak self] in self?.chooserWindow?.close() }
        chooserWindow = makeWindow(title: model.text("Choose an action"), size: NSSize(width: 520, height: 480),
                                   resizable: false, root: view)
        present(chooserWindow)
    }

    func openEditor(files: [URL], action: ActionItem) {
        guard !files.isEmpty else { return }
        let panel = makeWindow(title: action.title.lowercased(), size: NSSize(width: 1000, height: 680), resizable: true,
                               root: NativeFileEditor(model: model, files: files, action: action) { [weak self] in
            self?.managedWindows.values.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("MultiShift.Editor") && $0.isVisible })?.close()
        })
        panel.identifier = NSUserInterfaceItemIdentifier("MultiShift.Editor")
        MultiWindowPolicy.configure(panel, minimum: NSSize(width: 880, height: 560), maximum: MultiInterfaceMetrics.editorMaximum)
        present(panel)
        constrainEditorWindow(panel)
        DispatchQueue.main.async { [weak self, weak panel] in
            if let panel { self?.constrainEditorWindow(panel) }
        }
    }

    func confirmCombination(files: [URL], action: ActionItem) {
        weak var panel: NSWindow?
        let view = CombinationOrderView(model: model, files: files, confirm: { [weak self] ordered in
            panel?.close()
            self?.model.perform(action: action.id, files: ordered)
        }, cancel: { panel?.close() })
        let window = makeWindow(title: model.language == "ru" ? "Порядок файлов" : "File order", size: NSSize(width: 560, height: 480), resizable: true, root: view)
        panel = window
        present(window)
    }

    private func startInputMonitor() {
        inputTimer?.invalidate()
        inputTimer = nil
        guard model.enabled, ProcessInfo.processInfo.environment["MULTI_ECOSYSTEM_REVIEW"] == nil else { return }
        let interval = dragPanel == nil ? 0.035 : 1.0 / Double(max(60, dragPanel?.screen?.maximumFramesPerSecond ?? 60))
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollInput() }
        }
        timer.tolerance = dragPanel == nil ? 0.005 : 0
        inputTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func applicationWillTerminate(_ notification: Notification) {
        inputTimer?.invalidate()
        inputTimer = nil
        dragPanel?.orderOut(nil)
        if let wheelActivity { ProcessInfo.processInfo.endActivity(wheelActivity) }
        wheelActivity = nil
        if let commandQMonitor { NSEvent.removeMonitor(commandQMonitor) }
        if let screenParametersObserver { NotificationCenter.default.removeObserver(screenParametersObserver) }
        if let accessibilityOptionsObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityOptionsObserver) }
    }

    private func installCommandQMonitor() {
        commandQMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let extraModifiers: NSEvent.ModifierFlags = [.shift, .option, .control, .function]
            guard event.keyCode == 12,
                  modifiers.contains(.command),
                  modifiers.intersection(extraModifiers).isEmpty else { return event }
            self?.app.terminate(nil)
            return nil
        }
    }

    private func pollInput() {
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0
        let modifiers = NSEvent.modifierFlags
        let keyDown: Bool
        switch model.trigger {
        case "ctrl": keyDown = modifiers.contains(.control)
        case "alt": keyDown = modifiers.contains(.option)
        default: keyDown = modifiers.contains(.shift)
        }
        let escape = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(53))
        let position = NSEvent.mouseLocation

        if dragPanel != nil {
            let board = NSPasteboard(name: .drag)
            if board.changeCount != dragPasteboardChange {
                dragPasteboardChange = board.changeCount
                let current = dragFiles()
                if !current.isEmpty && current != wheelFiles { lastFiles = current; wheelFiles = current }
            }
            if escape { hideWheel(); return }
            if mouseDown {
                updateWheelSelection(at: position)
                if keyDown && !shiftWasDown { toggleWheelMode() }
            } else {
                updateWheelSelection(at: position)
                finishDragSelection()
            }
            shiftWasDown = keyDown
            return
        }

        guard model.enabled else { downAt = nil; shiftWasDown = keyDown; return }
        if mouseDown {
            if downAt == nil { downAt = position; triggerFired = false }
            if let start = downAt, !triggerFired,
               hypot(position.x - start.x, position.y - start.y) >= 10, keyDown {
                let files = dragFiles()
                if !files.isEmpty {
                    triggerFired = true
                    lastFiles = files
                    wheelFiles = files
                    model.wheel.mode = "convert"
                    model.wheel.items = model.formattedActions(for: files)
                    model.wheel.selectedIndex = nil
                    showWheel(at: position)
                }
            }
        } else {
            downAt = nil
            triggerFired = false
        }
        shiftWasDown = keyDown
    }

    private func dragFiles() -> [URL] {
        let board = NSPasteboard(name: .drag)
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls
    }

    private func toggleWheelMode() {
        let next = model.wheel.mode == "convert" ? "tools" : "convert"
        let actions = model.actions(for: wheelFiles, mode: next == "convert" ? nil : "tools")
        guard !actions.isEmpty else { return }
        wheelInteraction.begin(at: NSEvent.mouseLocation)
        model.wheel.mode = next
        model.wheel.items = actions
        model.wheel.selectedIndex = nil
    }

    private func showWheel(at position: NSPoint) {
        if let wheelActivity { ProcessInfo.processInfo.endActivity(wheelActivity) }
        // The Finder stays foreground. Keep this short user gesture out of App Nap.
        wheelActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
            reason: "radial file action selection")
        let screen = NSScreen.screens.first(where: { $0.frame.contains(position) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        wheelGeometry = WheelGeometry(diameter: min(400, visible.width, visible.height))
        let panel = NonActivatingPanel(contentRect: wheelGeometry.frame(near: position, visibleFrame: visible))
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)) + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // SwiftUI shadow has a deliberate 16 pt transparent margin.
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        model.wheel.isPresented = false
        model.wheel.selectedIndex = nil
        wheelInteraction.begin(at: position)
        dragPasteboardChange = NSPasteboard(name: .drag).changeCount
        panel.contentView = NSHostingView(rootView: WheelView(model: model, wheel: model.wheel, geometry: wheelGeometry))
        dragPanel = panel
        panel.orderFrontRegardless()
        shiftWasDown = true
        startInputMonitor()
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, self.dragPanel === panel else { return }
            withAnimation(MultiMotion.reduced ? nil : .timingCurve(0.23, 1, 0.32, 1,
                duration: MultiInterfaceMetrics.wheelEnterDuration)) { self.model.wheel.isPresented = true }
        }
    }

    private func updateWheelSelection(at position: NSPoint) {
        guard let panel = dragPanel else { return }
        wheelInteraction.update(cursor: position,
            localPoint: CGPoint(x: position.x - panel.frame.minX, y: panel.frame.maxY - position.y),
            geometry: wheelGeometry, count: model.wheel.items.count)
        if model.wheel.selectedIndex != wheelInteraction.selectedIndex {
            model.wheel.selectedIndex = wheelInteraction.selectedIndex
        }
    }

    private func finishDragSelection() {
        let files = lastFiles.isEmpty ? wheelFiles : lastFiles
        let selected = model.wheel.selectedIndex.flatMap { index in
            model.wheel.items.indices.contains(index) ? model.wheel.items[index] : nil
        }
        hideWheel()
        if let selected, !files.isEmpty { model.select(selected, files: files) }
    }

    private func hideWheel() {
        let outgoing = dragPanel
        let outgoingActivity = wheelActivity
        wheelActivity = nil
        dragPanel = nil
        wheelInteraction.cancel()
        if let outgoing {
            // Keep the outgoing hosting view and its in-flight presentation intact.
            // Its wheel object is detached below; a new gesture receives a new object.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = MultiMotion.reduced ? 0 : MultiInterfaceMetrics.wheelExitDuration
                context.timingFunction = MultiMotion.timing
                outgoing.animator().alphaValue = 0
            } completionHandler: {
                outgoing.orderOut(nil)
                if let outgoingActivity { ProcessInfo.processInfo.endActivity(outgoingActivity) }
            }
        } else if let outgoingActivity { ProcessInfo.processInfo.endActivity(outgoingActivity) }
        model.wheel = WheelPresentation()
        wheelFiles = []
        lastFiles = []
        downAt = nil
        triggerFired = false
        if outgoing != nil { startInputMonitor() }
    }

    func observeAppearance() {
        appearanceSubscription = model.$appearance.sink { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.app.windows.forEach(self.setAppearance)
                self.refreshStatusMenu()
                self.updateApplicationIcon()
            }
        }
    }

    /// Runs the packaged engine through AppModel and FileJobCoordinator using owned fixtures.
    private func runFunctionalAudit() {
        guard let root = MultiAuditEnvironment.root else { return }
        let input = root.appendingPathComponent("input.png")
        let broken = root.appendingPathComponent("broken.png")
        let original = try? Data(contentsOf: input)
        try? Data("invalid image fixture".utf8).write(to: broken)
        var results: [[String: Any]] = []
        let activeTimer = inputTimer?.isValid == true
        updateEnabled(false)
        let pausedTimer = inputTimer == nil
        updateEnabled(true)
        results.append(["case": "pause-resume", "passed": activeTimer && pausedTimer && inputTimer?.isValid == true])
        model.trigger = "ctrl"; model.jpgQuality = 83; model.pdfDPI = 220; model.saveSettings()
        let chosen = root.appendingPathComponent("chosen-results")
        do {
            try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
            try OutputFolderPreference.store(chosen, defaults: AppModel.defaults)
            model.output = "custom"; model.saveSettings()
        } catch { fatalError("Cannot prepare custom output audit: \(error)") }
        var step = 0
        var deadline = Date().addingTimeInterval(20)
        model.perform(action: "convert:JPG", files: [input])
        func poll() {
            guard let operation = self.model.recent.first else { finish(); return }
            if operation.status == .running && Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { poll() }; return
            }
            if step == 0 {
                let outputsExist = !operation.outputPaths.isEmpty && operation.outputPaths.allSatisfy { FileManager.default.fileExists(atPath: $0) }
                results.append(["case": "packaged-conversion", "status": operation.status.rawValue,
                    "passed": operation.status == .completed && outputsExist])
                results.append(["case": "custom-output-folder", "paths": operation.outputPaths,
                    "passed": operation.outputPaths.count == 1 && operation.outputPaths.allSatisfy {
                        URL(fileURLWithPath: $0).deletingLastPathComponent().resolvingSymlinksInPath().path == chosen.resolvingSymlinksInPath().path
                    }])
                self.model.undoOperation(id: operation.id)
                let undo = self.model.operation(id: operation.id)
                results.append(["case": "trash-only-undo", "status": undo?.status.rawValue ?? "missing", "passed": undo?.status == .undone])
                step = 1; deadline = Date().addingTimeInterval(20)
                self.model.perform(action: "convert:JPG", files: [input, broken])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { poll() }
            } else {
                results.append(["case": "partial-batch", "status": operation.status.rawValue,
                    "passed": operation.status == .partial && operation.failureCount == 1 && operation.outputPaths.count == 1])
                if let output = operation.outputPaths.first {
                    let url = URL(fileURLWithPath: output)
                    var data = (try? Data(contentsOf: url)) ?? Data(); data.append(0)
                    try? data.write(to: url)
                    self.model.undoOperation(id: operation.id)
                    results.append(["case": "changed-output-protected", "passed": FileManager.default.fileExists(atPath: output)
                        && self.model.operation(id: operation.id)?.status == .undoFailed])
                }
                finish()
            }
        }
        func finish() {
            self.updateEnabled(false)
            let report: [String: Any] = ["evidence": "normal functional path; packaged engine; isolated owned fixtures",
                "cases": results, "originalUnchanged": original != nil && original == (try? Data(contentsOf: input)),
                "timerAfterPause": self.inputTimer?.isValid == true,
                "diagnosticInAuditRoot": FileManager.default.fileExists(atPath: root.appendingPathComponent("diagnostics.jsonl").path),
                "settingsSaved": AppModel.defaults.integer(forKey: "jpg_quality") == 83
                    && AppModel.defaults.string(forKey: "trigger") == "ctrl"]
            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: root.appendingPathComponent("functional-results.json"))
            self.app.terminate(nil)
        }
        poll()
    }

    /// Native-window fixture audit; does not synthesize Finder events or execute an action.
    private func runCircleAudit(directory: String) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let fixture = URL(fileURLWithPath: directory).appendingPathComponent("fixture.png")
        var measurements: [[String: Any]] = []
        let cases: [(String, String, Int?)] = [
            ("light", "convert", nil), ("light", "convert", 0), ("dark", "convert", nil), ("dark", "convert", 8),
            ("light", "tools", 2), ("dark", "tools", 5)
        ]
        func capture(_ index: Int) {
            guard index < cases.count else {
                // Exercise interruption/reopening without changing a global mouse/keyboard state.
                var completed = 0
                func cycle() {
                    guard completed < 100 else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            let report: [String: Any] = ["evidence": "native-window fixture; not physical Finder drag",
                                "cycles": completed, "activePanelAfterClose": self.dragPanel != nil,
                                "inputTimerAfterClose": self.inputTimer?.isValid == true,
                                "activityAfterClose": self.wheelActivity != nil,
                                "systemReduceMotion": MultiMotion.reduced, "windows": measurements]
                            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                                .write(to: URL(fileURLWithPath: directory + "/circle-results.json"))
                            self.app.terminate(nil)
                        }
                        return
                    }
                    self.wheelFiles = [fixture]
                    self.model.wheel.items = self.model.formattedActions(for: [fixture])
                    let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 800)
                    self.showWheel(at: CGPoint(x: screen.midX, y: screen.midY))
                    // Mode change before queued entrance must not invalidate entrance work.
                    if completed % 2 == 0 { self.toggleWheelMode() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                        self.hideWheel(); completed += 1; cycle()
                    }
                }
                cycle()
                return
            }
            let (theme, mode, selection) = cases[index]
            self.model.appearance = theme
            self.model.wheel.mode = mode
            self.wheelFiles = [fixture]
            self.model.wheel.items = self.model.actions(for: [fixture], mode: mode == "tools" ? "tools" : nil)
            let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 800)
            self.showWheel(at: CGPoint(x: screen.midX, y: screen.midY))
            self.model.wheel.selectedIndex = selection
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let panel = self.dragPanel {
                    let name = "\(theme)-\(mode)-\(selection.map(String.init) ?? "cancel")"
                    MultiEcosystemProbe.capture(panel, path: directory + "/" + name + ".png")
                    measurements.append(["name": name, "framePt": [panel.frame.minX, panel.frame.minY, panel.frame.width, panel.frame.height],
                        "backingScale": panel.backingScaleFactor, "outerRadiusPt": self.wheelGeometry.outerRadius,
                        "cancelRadiusPt": self.wheelGeometry.cancelRadius, "itemCount": self.model.wheel.items.count,
                        "nativeWindowID": panel.windowNumber,
                        "allSymbolsAvailable": self.model.wheel.items.allSatisfy { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil) != nil }])
                }
                self.hideWheel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { capture(index + 1) }
            }
        }
        capture(0)
    }
}

private final class NonActivatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
