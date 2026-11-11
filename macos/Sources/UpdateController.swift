import AppKit
import SwiftUI
#if canImport(Sparkle)
import Sparkle
#endif

/// Owns only update preferences; file operations remain owned by AppModel.
@MainActor
final class UpdateController: NSObject, ObservableObject {
    static let shared = UpdateController()
    @Published var automaticChecks = AppModel.defaults.object(forKey: "updates.checks") as? Bool ?? true {
        didSet { AppModel.defaults.set(automaticChecks, forKey: "updates.checks"); configure() }
    }
    #if canImport(Sparkle)
    private var controller: SPUStandardUpdaterController?
    #endif
    var isConfigured: Bool {
        #if canImport(Sparkle)
        let info = Bundle.main.infoDictionary ?? [:]
        guard let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return false }
        return Data(base64Encoded: info["SUPublicEDKey"] as? String ?? "")?.count == 32
        #else
        return false
        #endif
    }
    func start() {
        guard MultiAuditEnvironment.root == nil, isConfigured else { return }
        #if canImport(Sparkle)
        if controller == nil {
            controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
            configure()
            controller?.startUpdater()
        }
        #endif
    }
    private func configure() {
        #if canImport(Sparkle)
        controller?.updater.automaticallyChecksForUpdates = automaticChecks
        controller?.updater.automaticallyDownloadsUpdates = false
        #endif
    }
    func checkNow() {
        start()
        #if canImport(Sparkle)
        controller?.checkForUpdates(nil)
        #endif
    }
}
#if canImport(Sparkle)
extension UpdateController: SPUUpdaterDelegate {
    @objc(updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard let delegate = NSApplication.shared.delegate as? AppDelegate,
              delegate.model.hasActiveFileOperations else { return false }
        Task { @MainActor [weak delegate] in
            while delegate?.model.hasActiveFileOperations == true {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            installHandler()
        }
        return true
    }
}
#endif

struct UpdateSettingsView: View {
    @ObservedObject private var updates = UpdateController.shared
    let russian: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(russian ? "обновления" : "updates").font(.system(size: 12, weight: .semibold))
            if updates.isConfigured {
                MultiNativeCheckbox(title: russian ? "проверять автоматически" : "check automatically", isOn: $updates.automaticChecks)
                MultiNativeAction(title: russian ? "проверить обновления" : "check for updates", action: updates.checkNow)
                Text(russian ? "установка — после подтверждения" : "installation requires confirmation")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(russian ? "обновления недоступны в этой локальной сборке" : "updates are unavailable in this local build")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
