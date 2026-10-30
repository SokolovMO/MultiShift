import AppKit

@main struct HistoryChecks {
    @MainActor static func main() throws {
        guard let root = MultiAuditEnvironment.root else { fatalError("isolated root required") }
        let file = root.appendingPathComponent("result.txt")
        try Data("preserved".utf8).write(to: file)
        func entry(_ status: OperationStatus) -> RecentOperation {
            RecentOperation(id: UUID(), actionTitle: "test", title: "fixture", detail: "", inputNames: [], outputPaths: [file.path], outputFingerprints: [], date: Date(), status: status, failureCount: 0)
        }
        let first = entry(.completed), second = entry(.failed)
        let url = root.appendingPathComponent("operations.json")
        try JSONEncoder().encode([first, second]).write(to: url)
        let model = AppModel()
        precondition(!entry(.running).canDeleteFromHistory)
        for status in [OperationStatus.completed, .partial, .failed, .cancelled, .undone, .undoFailed] {
            precondition(entry(status).canDeleteFromHistory)
        }
        try model.deleteHistoryEntry(id: first.id)
        precondition(model.recent.map(\.id) == [second.id])
        let contents = try String(contentsOf: file, encoding: .utf8)
        precondition(contents == "preserved")
        precondition(AppModel().recent.map(\.id) == [second.id])
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        do { try model.deleteHistoryEntry(id: second.id); fatalError("write failure swallowed") }
        catch { precondition(model.recent.map(\.id) == [second.id]) }
        print("HistoryChecks PASS: identity, file preservation, relaunch, running policy, write failure")
    }
}
