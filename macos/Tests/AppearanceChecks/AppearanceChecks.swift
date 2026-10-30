import AppKit
import SwiftUI

@main struct AppearanceChecks {
    @MainActor static func main() {
        precondition(MultiAuditEnvironment.root != nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        let model = delegate.model
        delegate.observeAppearance()
        Task { @MainActor in
            func settle() async { try? await Task.sleep(for: .milliseconds(250)) }
            app.appearance = nil
            let inherited = app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])!
            for _ in 0..<4 {
                for forced in ["dark", "light"] {
                    model.appearance = forced
                    _ = delegate.perform(NSSelectorFromString("showSettings"))
                    await settle()
                    let window = app.windows.first { $0.isVisible }!
                    window.close()
                    await settle()
                    _ = delegate.perform(NSSelectorFromString("showSettings"))
                    await settle()
                    model.appearance = "system"
                    await settle()
                    precondition(window.appearance == nil, "window retained an explicit override in system mode")
                    precondition(app.appearance == nil, "application retained an explicit override in system mode")
                    precondition(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == inherited, "window kept forced theme after system")
                    precondition(window.contentView!.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == inherited, "hosting view kept forced theme after system")
                }
            }
            print("AppearanceChecks PASS: dark/light to system, reopened settings, 8 transitions with no overrides")
            app.terminate(nil)
        }
        app.run()
    }
}
