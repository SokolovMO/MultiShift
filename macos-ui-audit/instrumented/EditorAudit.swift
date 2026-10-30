import AppKit
import SwiftUI

@main @MainActor struct EditorAudit {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        delegate.model.delegate = delegate
        app.setActivationPolicy(.regular)
        guard let root = MultiAuditEnvironment.root else { return }
        let image = root.appendingPathComponent("input.png")
        let pdf = root.appendingPathComponent("input.pdf")
        let imageActions = delegate.model.toolActions(for: [image])
        let pdfActions = delegate.model.toolActions(for: [pdf]).filter { ["tool:Compress", "tool:Protect", "tool:Metadata"].contains($0.id) }
        let cases = ["light", "dark"].flatMap { theme in
            imageActions.map { (theme, image, $0) } + pdfActions.map { (theme, pdf, $0) }
        }
        var results: [[String: Any]] = []
        func run(_ index: Int) {
            guard index < cases.count else {
                let report: [String: Any] = ["evidence": "canonical UI/model/engine with alternate audit entry point; no apply/save clicks",
                    "cases": results, "inputMonitorInstalled": false]
                try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: root.appendingPathComponent("editor-results.json"))
                app.terminate(nil); return
            }
            let (theme, file, action) = cases[index]
            delegate.model.appearance = theme
            delegate.openEditor(files: [file], action: action)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let window = app.windows.first { $0.isVisible && $0.identifier?.rawValue == "MultiShift.Editor" }
                let name = theme + "-" + file.pathExtension + "-" + action.id.replacingOccurrences(of: ":", with: "-")
                if let window {
                    MultiEcosystemProbe.capture(window, path: root.appendingPathComponent(name + ".png").path)
                    results.append(["name": name, "action": action.id, "opened": true,
                        "framePt": [window.frame.minX, window.frame.minY, window.frame.width, window.frame.height],
                        "backingScale": window.backingScaleFactor, "applyOrSaveTested": false])
                    window.close()
                } else { results.append(["name": name, "opened": false]) }
                run(index + 1)
            }
        }
        DispatchQueue.main.async { run(0) }
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
