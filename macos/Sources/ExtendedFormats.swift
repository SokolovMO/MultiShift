import AppKit
import SwiftUI

/// Mirrors the engine's supported families; optional Office routes fail with an actionable error.
enum ExtendedFormats {
    static let audio = Set("mp3 wav flac aac m4a m4b ogg oga opus wma aiff aif ac3 ape mka".split(separator: " ").map(String.init))
    static let video = Set("mp4 mkv webm mov avi wmv flv m4v mpg mpeg 3gp ts vob m2ts".split(separator: " ").map(String.init))
    static func isMedia(_ url: URL) -> Bool { audio.contains(url.pathExtension.lowercased()) || video.contains(url.pathExtension.lowercased()) }
    static func isImage(_ url: URL) -> Bool { Set(["png", "jpg", "jpeg", "webp", "heic", "heif", "tif", "tiff", "avif", "bmp", "gif", "ico"]).contains(url.pathExtension.lowercased()) }
    static func targets(_ url: URL) -> [String]? {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return ["ZIP", "TAR.GZ"] }
        let ext = url.pathExtension.lowercased()
        if audio.contains(ext) { return ["MP3", "WAV", "FLAC", "M4A", "AAC", "OGG", "OPUS", "WMA", "AIFF"] }
        if video.contains(ext) { return ["MP4", "MKV", "WEBM", "MOV", "AVI", "GIF", "MP3", "M4A", "WAV", "FLAC"] }
        switch ext {
        case "srt", "vtt", "ass", "ssa": return ["SRT", "VTT", "ASS"]
        case "csv", "tsv", "json", "xlsx", "xlsm", "xls", "ods": return ["XLSX", "CSV", "TSV", "JSON", "HTML", "MD", "PDF", "DOCX"]
        case "pptx", "ppt", "odp", "ppsx", "pps": return ["PDF", "PNG", "JPG", "TXT"]
        case "doc", "odt", "rtf", "dot": return ["PDF", "DOCX", "TXT"]
        case "md", "markdown": return ["PDF", "DOCX", "TXT", "HTML"]
        case "html", "htm", "xhtml": return ["PDF", "DOCX", "TXT", "MD"]
        case "epub", "mobi", "fb2": return ["PDF", "TXT", "HTML"]
        case "xps", "oxps", "cbz": return ["PDF"]
        case "svg": return ["PNG", "JPG", "WEBP", "TIFF", "PDF"]
        case "zip", "tar", "gz", "tgz", "xz", "txz", "bz2": return ["ZIP", "TAR", "TAR.GZ", "TAR.XZ", "TAR.BZ2"]
        default: return nil
        }
    }
}

enum OperationSummary {
    static func describe(_ metrics: [String: Any], language: String) -> String {
        var parts: [String] = []
        if let before = metrics["before_bytes"] as? Int64, let after = metrics["after_bytes"] as? Int64, before > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: before, countStyle: .file) + " → " + ByteCountFormatter.string(fromByteCount: after, countStyle: .file))
            let saving = Int((1 - Double(after) / Double(before)) * 100)
            if saving > 0 { parts.append("−\(saving)%") }
        }
        if let before = metrics["before_dimensions"] as? [Int], let after = metrics["after_dimensions"] as? [Int], before.count == 2, after.count == 2 {
            parts.append("\(before[0])×\(before[1]) → \(after[0])×\(after[1])")
        }
        if let pages = metrics["after_pages"] as? Int { parts.append(language == "ru" ? "страниц: \(pages)" : "pages: \(pages)") }
        if let duration = metrics["duration"] as? Double { parts.append(String(format: "%d:%02d", Int(duration)/60, Int(duration)%60)) }
        if metrics["silent_video"] as? Bool == true { parts.append(language == "ru" ? "без звука" : "no sound") }
        return parts.joined(separator: " · ")
    }
}

struct OperationFeedbackStrip: View {
    @ObservedObject var model: AppModel
    let operation: RecentOperation
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if operation.status == .running { ProgressView().controlSize(.small) }
            else { Image(systemName: operation.failureCount > 0 ? "exclamationmark.triangle" : "checkmark.circle") }
            VStack(alignment: .leading, spacing: 3) {
                Text(operation.actionTitle + " · " + operation.title).font(.headline)
                Text(operation.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            if let path = operation.outputPaths.first {
                Button(model.language == "ru" ? "Открыть" : "Open") { model.openOutput(at: path) }
            }
        }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct CombinationOrderView: View {
    @ObservedObject var model: AppModel
    @State private var files: [URL]
    let confirm: ([URL]) -> Void
    let cancel: () -> Void
    @State private var selected: URL?
    init(model: AppModel, files: [URL], confirm: @escaping ([URL]) -> Void, cancel: @escaping () -> Void) {
        self.model = model
        _files = State(initialValue: files)
        self.confirm = confirm
        self.cancel = cancel
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.language == "ru" ? "Выберите порядок файлов" : "Choose file order").font(.title2)
            Text(model.language == "ru" ? "Перетаскивайте строки или используйте кнопки. Порядок определяет страницы итогового документа или последовательность клипов." : "Drag rows or use the buttons. This order determines document pages or clip sequence.")
                .foregroundStyle(.secondary)
            List(selection: $selected) {
                ForEach(files, id: \.self) { url in
                    HStack { Image(systemName: "line.3.horizontal"); Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle) }.tag(url)
                }.onMove { offsets, destination in files.move(fromOffsets: offsets, toOffset: destination) }
            }.listStyle(.bordered)
            HStack {
                Button(model.language == "ru" ? "Выше" : "Move up") { move(-1) }.disabled(!canMove(-1))
                Button(model.language == "ru" ? "Ниже" : "Move down") { move(1) }.disabled(!canMove(1))
                Spacer()
                Button(model.text("Cancel"), action: cancel).keyboardShortcut(.cancelAction)
                Button(model.language == "ru" ? "Объединить" : "Combine") { confirm(files) }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(minWidth: 500, minHeight: 380)
    }
    private func canMove(_ delta: Int) -> Bool {
        guard let selected, let index = files.firstIndex(of: selected) else { return false }
        return files.indices.contains(index + delta)
    }
    private func move(_ delta: Int) {
        guard canMove(delta), let selected, let index = files.firstIndex(of: selected) else { return }
        files.swapAt(index, index + delta)
    }
}

extension AppModel {
    /// Both preview and tool requests use the same private staging and worker as Save Copy.
    func inspectCopy(_ url: URL, request: [String: Any], completion: @escaping ([String: Any]?, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let coordinator = FileJobCoordinator()
            do {
                let job = try coordinator.stage([url], id: UUID())
                defer { coordinator.remove(job) }
                var payload = request
                payload["path"] = job.inputs[0].stagedURL.path
                let response = try EngineClient().execute(executable: self.helperURL, request: payload)
                guard response["ok"] as? Bool == true else {
                    let detail = response["error"] as? String ?? self.text("Couldn't load preview")
                    DispatchQueue.main.async { completion(nil, EngineClient.safeDetail(detail)) }
                    return
                }
                DispatchQueue.main.async { completion(response, nil) }
            } catch {
                DispatchQueue.main.async { completion(nil, EngineClient.safeDetail(error.localizedDescription)) }
            }
        }
    }
}
