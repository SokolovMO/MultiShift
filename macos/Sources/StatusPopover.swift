import AppKit
import Combine

/// Shares the exact measured header/rows with MultiSwitcher, while keeping file models independent.
@MainActor final class ShiftStatusPopoverController: NSViewController {
    private let model: AppModel
    private let openFiles: () -> Void
    private let settings: () -> Void
    private let welcome: () -> Void
    private let details: (UUID) -> Void
    private let quit: () -> Void
    private let page = MultiPopoverView()
    private var subscription: AnyCancellable?
    private var refreshQueued = false
    private var historyExpanded = ProcessInfo.processInfo.environment["MULTI_ECOSYSTEM_HISTORY"] == "1"
    init(model: AppModel, openFiles: @escaping () -> Void, settings: @escaping () -> Void,
         welcome: @escaping () -> Void, details: @escaping (UUID) -> Void, quit: @escaping () -> Void,
         resize: @escaping (NSSize) -> Void, close: @escaping () -> Void) {
        self.model = model; self.openFiles = openFiles; self.settings = settings
        self.welcome = welcome; self.details = details; self.quit = quit
        super.init(nibName: nil, bundle: nil)
        page.onSize = { [weak self] size in
            self?.preferredContentSize = size
            resize(size)
        }; page.onEscape = close
        subscription = model.objectWillChange.sink { [weak self] _ in
            guard let self, !self.refreshQueued else { return }
            self.refreshQueued = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refreshQueued = false
                guard self.viewIfLoaded?.window?.isVisible == true else { return }
                self.refresh()
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("not supported") }
    override func loadView() { view = page; refresh() }
    private func text(_ ru: String, _ en: String) -> String { model.language == "ru" ? ru : en }
    func refresh(animated: Bool = false) {
        let dark = model.appearance == "dark" || model.appearance == "system" && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let icon = Bundle.main.url(forResource: dark ? "icon-dark" : "icon-light", withExtension: "png").flatMap(NSImage.init(contentsOf:)) ?? NSApp.applicationIconImage!
        page.configure(name: "multishift", status: model.enabled ? text("работает", "running") : text("приостановлен", "paused"), icon: icon,
            enabled: model.enabled, toggle: { [weak self] in guard let self else { return }; self.model.delegate?.updateEnabled(!self.model.enabled) })
        var items = [MultiPopoverItem(title: model.text("Open files…"), symbol: "doc.badge.plus", shortcut: "o", action: openFiles),
            MultiPopoverItem(title: model.text("Recent operations"), symbol: historyExpanded ? "chevron.down" : "chevron.right", id: "recent-operations", action: { [weak self] in self?.toggleHistory() })]
        let recent = historyExpanded ? Array(model.recent.prefix(20)) : Array(model.recent.prefix(1))
        if recent.isEmpty {
            items.append(MultiPopoverItem(title: model.text("No recent operations"), detail: text("удерживайте клавишу при перетаскивании файла", "hold the trigger while dragging a file"), symbol: "clock", enabled: false))
        } else {
            items += recent.map { operation in
                MultiPopoverItem(title: operation.title.lowercased(), detail: operation.inputNames.first ?? operation.actionTitle.lowercased(), symbol: operation.status.symbol,
                    fileName: true, id: operation.id.uuidString, action: { [weak self] in self?.details(operation.id) })
            }
        }
        for index in items.indices {
            if let id = UUID(uuidString: items[index].id), model.operation(id: id)?.status != .running {
                items[index].deletion = { [weak self] in self?.deleteHistory(id) }
            }
        }
        let footer = [MultiPopoverItem(title: text("настройки…", "settings…"), symbol: "slider.horizontal.3", shortcut: ",", action: settings),
            MultiPopoverItem(title: text("справка", "help"), symbol: "questionmark.circle", action: welcome),
            MultiPopoverItem(title: text("выход", "quit"), symbol: "power", shortcut: "q", action: quit)]
        page.setItems(items, footer: footer, animated: animated, maximumBodyHeight: 250)
    }
    private func deleteHistory(_ id: UUID) {
        guard let operation = model.operation(id: id), operation.status != .running else { return }
        // A transient popover closes when a sheet opens; use its explicit details window.
        details(id)
        model.delegate?.deleteHistoryEntry(id: id)
    }
    private func toggleHistory() { historyExpanded.toggle(); refresh(animated: true) }
    func toggleHistoryForReview() { toggleHistory() }
    var reviewGeometry: [String: Any] { page.reviewGeometry }
}
