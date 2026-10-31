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
    @Published var channel = AppModel.defaults.string(forKey: "updates.channel") ?? "stable" {
        didSet {
            AppModel.defaults.set(channel, forKey: "updates.channel")
            #if canImport(Sparkle)
            controller?.updater.resetUpdateCycleAfterShortDelay()
            #endif
        }
    }
    #if canImport(Sparkle)
    private var controller: SPUStandardUpdaterController?
    #endif
    var isConfigured: Bool {
        #if canImport(Sparkle)
        let info = Bundle.main.infoDictionary ?? [:]
        return (info["SUFeedURL"] as? String) == "https://sokolovmo.github.io/multi-releases/MultiShift/appcast.xml"
            && Data(base64Encoded: info["SUPublicEDKey"] as? String ?? "")?.count == 32
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
    func allowedChannels(for updater: SPUUpdater) -> Set<String> { channel == "beta" ? ["beta"] : [] }
}
#endif

struct UpdateSettingsView: View {
    @ObservedObject private var updates = UpdateController.shared
    let russian: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(russian ? "обновления" : "updates").font(.headline)
            if updates.isConfigured {
                Toggle(russian ? "проверять автоматически" : "check automatically", isOn: $updates.automaticChecks)
                Picker(russian ? "канал" : "channel", selection: $updates.channel) {
                    Text("stable").tag("stable")
                    Text("beta").tag("beta")
                }
                Button(russian ? "проверить обновления" : "check for updates") { updates.checkNow() }
                Text(russian ? "установка — после подтверждения" : "installation requires confirmation")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(russian ? "обновления недоступны в этой локальной сборке" : "updates are unavailable in this local build")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
