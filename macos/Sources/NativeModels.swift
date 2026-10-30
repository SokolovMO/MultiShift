import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI
import Darwin

struct ActionItem: Identifiable, Equatable {
    let id: String                 // Stable processing identifier, e.g. "convert:PNG".
    let title: String
    let shortTitle: String
    let hint: String
    let symbol: String
    var isTool: Bool { id.hasPrefix("tool:") }
}

struct PreviewInfo {
    let url: URL
    let width: Int
    let height: Int
    let sourceWidth: Int
    let sourceHeight: Int
}

enum OperationStatus: String, Codable {
    case running, completed, partial, failed, cancelled, undone, undoFailed
}

struct OperationFailure: Codable, Identifiable {
    var id: String { "\(inputIndex ?? -1)-\(code)-\(fileName)" }
    let inputIndex: Int?
    let fileName: String
    let stage: String
    let code: String
    let message: String
}

private struct EngineRequestError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct OutputFingerprint: Codable, Equatable {
    let path: String
    let device: Int64
    let fileNumber: Int64
    let size: Int64
    let modifiedAt: Date

    static func capture(_ path: String) -> OutputFingerprint? {
        let url = URL(fileURLWithPath: path)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              attrs[.type] as? FileAttributeType == .typeRegular,
              let device = (attrs[.systemNumber] as? NSNumber)?.int64Value,
              let number = (attrs[.systemFileNumber] as? NSNumber)?.int64Value,
              let size = (attrs[.size] as? NSNumber)?.int64Value,
              let modified = attrs[.modificationDate] as? Date else { return nil }
        let millisecondDate = Date(timeIntervalSince1970: floor(modified.timeIntervalSince1970 * 1000) / 1000)
        return OutputFingerprint(path: url.standardizedFileURL.path, device: device,
                                 fileNumber: number, size: size, modifiedAt: millisecondDate)
    }

    func stillMatches() -> Bool { Self.capture(path) == self }
}

struct RecentOperation: Identifiable, Codable {
    let id: UUID
    var actionTitle: String
    var title: String
    var detail: String
    var inputNames: [String]
    var outputPaths: [String]
    var outputFingerprints: [OutputFingerprint]
    var date: Date
    var status: OperationStatus
    var failureCount: Int
    var failures: [OperationFailure]? = nil
    var notificationDelivery: String? = nil
    var engineVersion: String? = nil

    var canDeleteFromHistory: Bool { status != .running }

    var canUndo: Bool {
        (status == .completed || status == .partial || status == .undoFailed)
            && !outputPaths.isEmpty
            && outputFingerprints.count == outputPaths.count
    }
}

/// Fast pointer updates invalidate only the radial surface, never settings/history.
final class WheelPresentation: ObservableObject {
    @Published var items: [ActionItem] = []
    @Published var selectedIndex: Int?
    @Published var mode = "convert"
    @Published var isPresented = false


}

final class AppModel: ObservableObject {
    static let bundleID = "com.multiswitcher.multishift"
    static let defaults: UserDefaults = MultiAuditEnvironment.root == nil
        ? (UserDefaults(suiteName: bundleID) ?? .standard)
        : MultiAuditEnvironment.defaults(appID: bundleID)
    static let settingsKeys = ["language", "appearance", "trigger", "output", "jpg_quality", "pdf_dpi", "welcomed"]

    @Published var enabled = true
    @Published var language: String
    @Published var appearance: String
    @Published var trigger: String
    @Published var output: String
    @Published var jpgQuality: Int
    @Published var pdfDPI: Int
    @Published var loginEnabled: Bool
    @Published var welcomeDemoPlayed = AppModel.defaults.bool(forKey: "welcomeDemoPlayed")
    var wheel = WheelPresentation()
    @Published private(set) var busyFiles: [String] = []
    @Published private(set) var longRunningOperationCount = 0
    @Published var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    @Published var increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    @Published private(set) var recent: [RecentOperation] = []
    @Published private(set) var notificationPermission = "unknown"
    @Published private(set) var notificationLastResult = ""

    weak var delegate: AppDelegate?
    let helperURL: URL
    private var activeOperations: [UUID: [URL]] = [:]
    private var operationStartTimes: [UUID: TimeInterval] = [:]
    private var progressOperations = Set<UUID>()
    private var undoOperations = Set<UUID>()
    private var menuSubscriptions = Set<AnyCancellable>()

    init() {
        Self.migrateOldSettings()
        language = Self.defaults.string(forKey: "language") ?? "ru"
        appearance = Self.defaults.string(forKey: "appearance") ?? "system"
        trigger = Self.defaults.string(forKey: "trigger") ?? "shift"
        output = Self.defaults.string(forKey: "output") ?? "next"
        jpgQuality = Self.defaults.object(forKey: "jpg_quality") as? Int ?? 90
        pdfDPI = Self.defaults.object(forKey: "pdf_dpi") as? Int ?? 200
        loginEnabled = Self.hasLegacyLoginAgent()
        helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/MultiShiftEngine/MultiShiftEngine")
        notificationPermission = text("Unknown")
        recent = Self.loadOperations()
        for index in recent.indices where recent[index].status == .running {
            recent[index].status = .failed
            recent[index].title = text("Operation interrupted")
            recent[index].detail = text("MultiShift closed before this operation finished.")
        }
        recent = Array(recent.prefix(20))
        Self.saveOperations(recent)
        $language.sink { [weak self] _ in Task { @MainActor [weak self] in self?.delegate?.refreshStatusMenu() } }.store(in: &menuSubscriptions)
        $recent.sink { [weak self] _ in Task { @MainActor [weak self] in self?.delegate?.refreshStatusMenu() } }.store(in: &menuSubscriptions)
        $enabled.sink { [weak self] _ in Task { @MainActor [weak self] in self?.delegate?.enabledStateDidChange() } }.store(in: &menuSubscriptions)
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    func text(_ key: String) -> String {
        guard language == "ru" else { return key.lowercased() }
        return ([
            "Welcome to MultiShift": "Добро пожаловать в MultiShift",
            "Move files through a faster workflow.": "Передвигайте файлы по короткому рабочему пути.",
            "Drag a file, hold Shift, choose an action.": "Перетащите файл, удерживайте Shift и выберите действие.",
            "Start using MultiShift": "Начать работу",
            "Settings…": "Настройки…",
            "Settings": "Настройки",
            "General": "Основные",
            "Files": "Файлы",
            "About": "О приложении",
            "Show Sidebar": "Показать боковую панель",
            "Hide Sidebar": "Скрыть боковую панель",
            "Appearance": "Оформление",
            "System": "Как в macOS",
            "Light": "Светлое",
            "Dark": "Тёмное",
            "Language": "Язык",
            "English": "Английский",
            "Russian": "Русский",
            "Open the menu with": "Открывать меню клавишей",
            "Save results": "Сохранять результаты",
            "Next to the original": "Рядом с исходным файлом",
            "In a MultiShift folder": "В папке MultiShift",
            "JPG / WebP quality": "Качество JPG / WebP",
            "PDF image resolution": "Разрешение PDF → изображения",
            "Open MultiShift at login": "Запускать MultiShift при входе",
            "All operations make a copy. Originals are preserved.": "Все операции создают копию. Исходные файлы сохраняются.",
            "Native macOS shell · Python processing engine": "Нативная оболочка macOS · обработка на Python",
            "Drag a file here": "Перетащите сюда файл",
            "Choose a file to get started": "Выберите файл, чтобы начать",
            "Convert": "Форматы",
            "Tools": "Инструменты",
            "Formats": "Форматы",
            "Choose an action": "Выберите действие",
            "Press Return or double-click to open.": "Нажмите Return или дважды щёлкните, чтобы открыть.",
            "Open files…": "Открыть файлы…",
            "How to use": "Как пользоваться",
            "Quit MultiShift": "Завершить MultiShift",
            "Show in Finder": "Показать в Finder",
            "Undo": "Отменить",
            "Close": "Закрыть",
            "Preview": "Предпросмотр",
            "Fit": "Вписать",
            "Actual Size": "100%",
            "Before": "До",
            "After": "После",
            "Save Copy": "Сохранить копию",
            "Cancel": "Отмена",
            "Crop": "Обрезка",
            "Add BG": "Добавить фон",
            "Annotate": "Разметка",
            "Redact": "Скрыть области",
            "Edit": "Коррекция",
            "Metadata": "Метаданные",
            "Compress": "Сжать",
            "Resize": "Изменить размер",
            "Protect": "Защитить PDF",
            "Quality": "Качество",
            "Maximum side": "Длинная сторона",
            "Width": "Ширина",
            "Height": "Высота",
            "Keep proportions": "Сохранять пропорции",
            "Password": "Пароль",
            "Confirm password": "Повторите пароль",
            "Remove all metadata": "Удалить все метаданные",
            "Remove location only": "Удалить только геоданные",
            "Black redaction": "Чёрное скрытие",
            "Background padding": "Отступ фона",
            "Corner radius": "Скругление углов",
            "Brightness": "Яркость",
            "Contrast": "Контраст",
            "Saturation": "Насыщенность",
            "Warmth": "Теплота",
            "Sharpness": "Резкость",
            "Rotate": "Поворот",
            "Use the drag area to select a region.": "Выделите область прямо на изображении.",
            "Completed": "Готово",
            "Couldn't finish": "Не удалось завершить",
            "Couldn't load preview": "Не удалось загрузить предпросмотр",
            "The source files were not changed.": "Исходные файлы не менялись.",
            "No files were created.": "Файлы не созданы.",
            "Something went wrong.": "Что-то пошло не так.",
            "Recent operations": "Недавние операции",
            "Pause MultiShift": "Приостановить MultiShift",
            "Resume MultiShift": "Возобновить MultiShift",
            "No recent operations": "Пока нет операций",
            "Operation details": "Подробности операции",
            "Show outputs in Finder": "Показать результаты в Finder",
            "No output files": "Нет готовых файлов",
            "Partial result": "Готово частично",
            "Failed": "Ошибка",
            "Cancelled": "Отменено",
            "Operation cancelled.": "Операция отменена.",
            "Working…": "Выполняется…",
            "The processing engine stopped unexpectedly.": "Модуль обработки неожиданно завершился.",
            "MultiShift cannot read this file. Choose it again in the file picker.": "MultiShift не может прочитать файл. Выберите его повторно в окне файлов.",
            "Choose another output folder to save the completed files.": "Выберите другую папку, чтобы сохранить готовые файлы.",
            "The results could not be saved to the selected folder.": "Не удалось сохранить результаты в выбранную папку.",
            "Notifications": "Уведомления",
            "Permission": "Разрешение",
            "Last send": "Последняя отправка",
            "Test notification": "Проверить уведомление",
            "Open macOS settings": "Открыть настройки macOS",
            "macOS may hide banners during Focus or screen sharing. Operation results remain available in MultiShift.": "macOS может скрывать баннеры при Фокусировании или демонстрации экрана. Результаты операций остаются в MultiShift.",
            "Unknown": "не проверено",
            "Allowed": "Разрешены",
            "Not requested": "Не запрашивались",
            "Denied": "Запрещены",
            "Transmitted to macOS": "Передано macOS",
            "Permission is required": "Нужно разрешение",
            "Sending failed": "Не удалось отправить",
            "Not sent": "Не отправлено",
            "Undone": "Отменено",
            "Undo failed": "Не удалось отменить",
            "Some output files changed and were left untouched.": "Некоторые результаты изменились — они оставлены без изменений.",
            "Output files moved to Trash.": "Результаты перемещены в Корзину.",
            "Operation interrupted": "Операция прервана",
            "MultiShift closed before this operation finished.": "MultiShift закрылся до завершения операции.",
            "Operation history is stored on this Mac.": "История операций хранится на этом Mac.",
            "Operation in progress": "Операция выполняется",
            "operations": "операций",
            "Input files": "Исходные файлы",
            "Output files": "Результаты",
            "Application": "Приложение",
            "Version": "Версия",
            "Done": "Готово",
            "Open": "Открыть",
            "Choose": "Выбрать",
            "Fit to Window": "Вписать в окно",
            "Crop Image": "Обрезка изображения",
            "Add a background": "Добавить фон",
            "Annotate image": "Разметить изображение",
            "Hide private areas": "Скрыть личные области",
            "Adjust image": "Настроить изображение",
            "Review metadata": "Посмотреть метаданные",
            "Compress file": "Сжать файл",
            "Resize image": "Изменить размер изображения",
            "Protect document": "Защитить документ",
            "Select files": "Выберите файлы",
            "Mixed file types are skipped.": "Файлы других типов будут пропущены.",
            "Select region": "Выделить область",
            "Redaction area": "Область скрытия",
            "Text annotation": "Текстовая подпись",
            "Annotation text": "Текст подписи",
            "Output folder": "Папка результатов",
            "Format": "Формат",
            "File": "Файл",
            "Originals are never modified.": "Исходные файлы не меняются.",
        ][key] ?? key).lowercased()
    }

    func saveSettings() {
        Self.defaults.set(language, forKey: "language")
        Self.defaults.set(appearance, forKey: "appearance")
        Self.defaults.set(trigger, forKey: "trigger")
        Self.defaults.set(output, forKey: "output")
        Self.defaults.set(jpgQuality, forKey: "jpg_quality")
        Self.defaults.set(pdfDPI, forKey: "pdf_dpi")
    }

    func markWelcomeDemoPlayed() {
        welcomeDemoPlayed = true
        Self.defaults.set(true, forKey: "welcomeDemoPlayed")
    }

    func refreshAccessibilityDisplayOptions() {
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        if reduceTransparency != opaque { reduceTransparency = opaque }
        if increaseContrast != contrast { increaseContrast = contrast }
    }

    func actions(for paths: [URL], mode: String? = nil) -> [ActionItem] {
        guard let first = paths.first else { return [] }
        let ext = first.pathExtension.lowercased()
        let image = ["png", "jpg", "jpeg", "webp", "heic", "heif", "tif", "tiff", "avif", "bmp", "gif", "ico"].contains(ext)
        let pdf = ext == "pdf"
        let docx = ext == "docx"
        let textFile = ["txt", "md", "csv", "log", "json", "xml", "html", "htm"].contains(ext)
        let targets: [String]
        if image { targets = ["PNG", "JPG", "WEBP", "HEIC", "TIFF", "AVIF", "BMP", "PDF", "ICO", "GIF"] }
        else if pdf { targets = ["JPG", "PNG", "DOCX", "TXT"] }
        else if docx { targets = ["PDF", "TXT"] }
        else if textFile { targets = ["PDF", "DOCX"] }
        else { return [] }
        let formatItems = targets.map { target in
            ActionItem(id: "convert:\(target)", title: target.lowercased(), shortTitle: target.lowercased(),
                       hint: Self.formatHint(target, language: language), symbol: Self.formatSymbol(target))
        }
        guard mode != "tools" else {
            var names: [(String, String, String, String)] = []
            if image {
                names = [
                    ("Compress", "Сжать", "Compress", "arrow.down.right.and.arrow.up.left"),
                    ("Resize", "Размер", "Resize", "arrow.up.left.and.arrow.down.right"),
                    ("Crop", "Обрезка", "Crop", "crop.rotate"),
                    ("Edit", "Правка", "Edit", "slider.horizontal.3"),
                    ("Annotate", "Разметка", "Annotate", "pencil.tip.crop.circle"),
                    ("Redact", "Скрыть", "Redact", "eye.slash"),
                    ("Add BG", "Фон", "Add BG", "square.stack.3d.up"),
                    ("Metadata", "Данные", "Metadata", "info.circle"),
                ]
            } else if pdf {
                names = [
                    ("Compress", "Сжать", "Compress", "arrow.down.right.and.arrow.up.left"),
                    ("Split", "Разделить", "Split", "scissors"),
                    ("Rotate", "Поворот", "Rotate", "rotate.right"),
                ]
                if paths.count > 1 { names.append(("Merge", "Объединить", "Merge", "doc.on.doc")) }
                names += [
                    ("Protect", "Защитить", "Protect", "lock.shield"),
                    ("Extract", "Извлечь", "Extract", "photo.on.rectangle.angled"),
                    ("Metadata", "Данные", "Metadata", "info.circle"),
                ]
            }
            return names.map { key, ru, en, icon in
                ActionItem(id: "tool:\(key)", title: (language == "ru" ? ru : en).lowercased(),
                           shortTitle: (language == "ru" ? ru : en).lowercased(),
                           hint: Self.toolHint(key, language: language), symbol: icon)
            }
        }
        return formatItems
    }

    private static func formatSymbol(_ format: String) -> String {
        switch format {
        case "PDF": return "doc.richtext"
        case "DOCX": return "doc.text"
        case "TXT": return "doc.plaintext"
        case "ICO": return "app"
        case "GIF": return "play.rectangle"
        default: return "photo"
        }
    }

    func formattedActions(for paths: [URL]) -> [ActionItem] { actions(for: paths) }
    func toolActions(for paths: [URL]) -> [ActionItem] { actions(for: paths, mode: "tools") }

    func select(_ action: ActionItem, files: [URL]) {
        let editor = ["Crop", "Add BG", "Annotate", "Redact", "Edit", "Metadata", "Compress", "Resize", "Protect"]
        if action.isTool, editor.contains(action.id.replacingOccurrences(of: "tool:", with: "")) {
            let name = action.id.replacingOccurrences(of: "tool:", with: "")
            let firstOnly = ["Crop", "Add BG", "Annotate", "Redact", "Edit", "Metadata", "Protect"].contains(name)
            let selected = firstOnly ? Array(files.prefix(1)) : files
            Task { @MainActor [weak self] in self?.delegate?.openEditor(files: selected, action: action) }
        } else {
            perform(action: action.id, files: files)
        }
    }

    func perform(action: String, files: [URL], parameters: [String: Any] = [:], completion: (([String]) -> Void)? = nil) {
        guard !files.isEmpty else { return }
        let operationID = UUID()
        recordOperation(id: operationID, action: action, files: files, outputs: [],
                        failures: [], status: .running,
                        detail: language == "ru" ? "выполняется…" : "working…", postNotification: false)
        activeOperations[operationID] = files
        operationStartTimes[operationID] = ProcessInfo.processInfo.systemUptime
        refreshOperationState()
        let progress = DispatchWorkItem { [weak self] in
            guard let self, self.activeOperations[operationID] != nil else { return }
            self.progressOperations.insert(operationID)
            self.longRunningOperationCount = self.progressOperations.count
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150), execute: progress)
        executeOperation(id: operationID, action: action, files: files, parameters: parameters,
                         retriedAccessIndices: [], progress: progress, completion: completion)
    }

    func preview(url: URL, maxSide: Int = 1800,
                 completion: @escaping (PreviewInfo?, [String: String], String?) -> Void) {
        preview(url: url, maxSide: maxSide, mayRequestAccess: true, completion: completion)
    }

    private func preview(url: URL, maxSide: Int, mayRequestAccess: Bool,
                         completion: @escaping (PreviewInfo?, [String: String], String?) -> Void) {
        let coordinator = FileJobCoordinator()
        let id = UUID()
        DispatchQueue.global(qos: .userInitiated).async {
            var stagedJob: StagedJob?
            var previewURL: URL?
            do {
                let job = try coordinator.stage([url], id: id)
                stagedJob = job
                let stagedURL = job.inputs[0].stagedURL
                let requestID = UUID().uuidString
                let previewResponse = try EngineClient().execute(executable: self.helperURL, request: [
                    "request_id": requestID, "operation": "preview", "path": stagedURL.path, "max_side": maxSide
                ])
                guard let preview = previewResponse["preview"] as? [String: Any],
                      let previewPath = preview["path"] as? String else {
                    let message = (previewResponse["failures"] as? [[String: Any]])?.first?["message"] as? String
                        ?? previewResponse["error"] as? String ?? self.text("Couldn't load preview")
                    throw EngineRequestError(message: EngineClient.safeDetail(message))
                }
                previewURL = URL(fileURLWithPath: previewPath)
                let info = PreviewInfo(url: previewURL!,
                                       width: preview["width"] as? Int ?? 1,
                                       height: preview["height"] as? Int ?? 1,
                                       sourceWidth: preview["source_width"] as? Int ?? 1,
                                       sourceHeight: preview["source_height"] as? Int ?? 1)
                let metadata = try EngineClient().execute(executable: self.helperURL, request: [
                    "request_id": UUID().uuidString, "operation": "inspect", "path": stagedURL.path
                ])
                coordinator.remove(job)
                DispatchQueue.main.async { completion(info, metadata["fields"] as? [String: String] ?? [:], nil) }
            } catch FileJobError.accessDenied {
                if mayRequestAccess {
                    DispatchQueue.main.async {
                        self.delegate?.requestFileAccess(for: url) { selected in
                            guard let selected else {
                                completion(nil, [:], self.text("Operation cancelled."))
                                return
                            }
                            self.preview(url: selected, maxSide: maxSide, mayRequestAccess: false, completion: completion)
                        }
                    }
                } else {
                    DispatchQueue.main.async { completion(nil, [:], self.text("MultiShift cannot read this file. Choose it again in the file picker.")) }
                }
            } catch {
                if let previewURL { try? FileManager.default.removeItem(at: previewURL) }
                let safe = EngineClient.safeDetail(error.localizedDescription)
                DispatchQueue.main.async { completion(nil, [:], safe.isEmpty ? self.text("Couldn't load preview") : safe) }
            }
            if let stagedJob { coordinator.remove(stagedJob) }
        }
    }

    func showPathsInFinder(_ files: [String]) {
        let urls = files.map(URL.init(fileURLWithPath:))
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func executeOperation(id: UUID, action: String, files: [URL], parameters: [String: Any],
                                   retriedAccessIndices: Set<Int>, progress: DispatchWorkItem,
                                   completion: (([String]) -> Void)?) {
        let coordinator = FileJobCoordinator()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let job = try coordinator.stage(files, id: id)
                let request: [String: Any] = [
                    "request_id": id.uuidString, "action": action,
                    "files": job.inputs.map { $0.stagedURL.path },
                    "parameters": parameters,
                    "settings": ["output": self.output, "jpg_quality": self.jpgQuality, "pdf_dpi": self.pdfDPI],
                ]
                let response = try EngineClient().execute(executable: self.helperURL, request: request)
                let rawOutputs = response["outputs"] as? [String] ?? []
                let failureObjects = response["failures"] as? [[String: Any]] ?? []
                let engineVersion = response["engine_version"] as? String
                let operationFailures = failureObjects.map { value in
                    OperationFailure(inputIndex: value["input_index"] as? Int,
                                     fileName: value["file"] as? String ?? "",
                                     stage: value["stage"] as? String ?? "convert",
                                     code: value["code"] as? String ?? "conversion_failed",
                                     message: EngineClient.safeDetail(value["message"] as? String ?? "The file could not be processed."))
                }
                do {
                    let published = try coordinator.publish(rawOutputs, from: job)
                    coordinator.remove(job)
                    DispatchQueue.main.async {
                        self.finishOperation(id: id, action: action, files: files, outputs: published,
                                             failures: operationFailures, progress: progress,
                                             completion: completion, engineVersion: engineVersion)
                    }
                } catch let saveFailure as FilePublishFailure {
                    if let fileError = saveFailure.underlying as? FileJobError,
                       case .invalidOutput = fileError {
                        coordinator.remove(job)
                        let failure = OperationFailure(inputIndex: nil, fileName: "", stage: "engine",
                                                       code: "invalid_output",
                                                       message: "The processing engine returned an invalid result path.")
                        DispatchQueue.main.async {
                            self.finishOperation(id: id, action: action, files: files,
                                                 outputs: saveFailure.published,
                                                 failures: operationFailures + [failure], progress: progress,
                                                 completion: completion, engineVersion: engineVersion)
                        }
                        return
                    }
                    let alreadyPublished = saveFailure.published
                    let remaining = saveFailure.remaining
                    DispatchQueue.main.async {
                        self.delegate?.requestOutputFolder { folder in
                            guard let folder else {
                                coordinator.remove(job)
                                let failures = operationFailures + [OperationFailure(
                                    inputIndex: nil, fileName: "", stage: "save", code: "save_cancelled",
                                    message: self.text("Choose another output folder to save the completed files."))]
                                self.finishOperation(id: id, action: action, files: files,
                                                     outputs: alreadyPublished, failures: failures,
                                                     progress: progress, completion: completion,
                                                     engineVersion: engineVersion)
                                return
                            }
                            DispatchQueue.global(qos: .userInitiated).async {
                                do {
                                    let saved = try coordinator.publish(remaining, from: job, alternateDestination: folder)
                                    coordinator.remove(job)
                                    DispatchQueue.main.async {
                                        self.finishOperation(id: id, action: action, files: files,
                                                             outputs: alreadyPublished + saved,
                                                             failures: operationFailures, progress: progress,
                                                             completion: completion, engineVersion: engineVersion)
                                    }
                                } catch {
                                    coordinator.remove(job)
                                    let saveError = OperationFailure(
                                        inputIndex: nil, fileName: "", stage: "save", code: "save_failed",
                                        message: self.text("The results could not be saved to the selected folder."))
                                    DispatchQueue.main.async {
                                        self.finishOperation(id: id, action: action, files: files,
                                                             outputs: alreadyPublished,
                                                             failures: operationFailures + [saveError],
                                                             progress: progress, completion: completion,
                                                             engineVersion: engineVersion)
                                    }
                                }
                            }
                        }
                    }
                }
            } catch FileJobError.accessDenied(let index) {
                guard files.indices.contains(index), !retriedAccessIndices.contains(index) else {
                    DispatchQueue.main.async {
                        self.finishOperation(id: id, action: action, files: files, outputs: [],
                                             failures: [OperationFailure(inputIndex: index,
                                                                         fileName: files.indices.contains(index) ? files[index].lastPathComponent : "",
                                                                         stage: "read", code: "permission_denied",
                                                                         message: self.text("MultiShift cannot read this file. Choose it again in the file picker."))],
                                             progress: progress, completion: completion)
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.delegate?.requestFileAccess(for: files[index]) { selected in
                        guard let selected else {
                            self.finishOperation(id: id, action: action, files: files, outputs: [], failures: [],
                                                 status: .cancelled, detail: self.text("Operation cancelled."),
                                                 progress: progress, completion: completion, postNotification: false)
                            return
                        }
                        var retriedFiles = files
                        retriedFiles[index] = selected
                        self.activeOperations[id] = retriedFiles
                        self.refreshOperationState()
                        self.executeOperation(id: id, action: action, files: retriedFiles, parameters: parameters,
                                              retriedAccessIndices: retriedAccessIndices.union([index]),
                                              progress: progress, completion: completion)
                    }
                }
            } catch FileJobError.missingInput(let index) {
                DispatchQueue.main.async {
                    self.finishOperation(id: id, action: action, files: files, outputs: [],
                                         failures: [OperationFailure(inputIndex: index,
                                                                     fileName: files.indices.contains(index) ? files[index].lastPathComponent : "",
                                                                     stage: "read", code: "input_missing",
                                                                     message: "The source file could not be found.")],
                                         progress: progress, completion: completion)
                }
            } catch FileJobError.unsupportedInput(let index) {
                DispatchQueue.main.async {
                    self.finishOperation(id: id, action: action, files: files, outputs: [],
                                         failures: [OperationFailure(inputIndex: index,
                                                                     fileName: files.indices.contains(index) ? files[index].lastPathComponent : "",
                                                                     stage: "validate", code: "unsupported_input",
                                                                     message: "Choose a file rather than a folder.")],
                                         progress: progress, completion: completion)
                }
            } catch {
                let safe = EngineClient.safeDetail(error.localizedDescription)
                let failure = OperationFailure(inputIndex: nil, fileName: "", stage: "engine",
                                               code: "engine_error",
                                               message: safe.isEmpty ? self.text("The processing engine stopped unexpectedly.") : safe)
                self.writeDiagnostic(operationID: id, engineVersion: nil,
                                     stage: failure.stage, code: failure.code, detail: failure.message)
                DispatchQueue.main.async {
                    self.finishOperation(id: id, action: action, files: files, outputs: [],
                                         failures: [failure], progress: progress, completion: completion)
                }
            }
        }
    }

    private func finishOperation(id: UUID, action: String, files: [URL], outputs: [URL],
                                 failures: [OperationFailure], status explicitStatus: OperationStatus? = nil,
                                 detail explicitDetail: String? = nil, progress: DispatchWorkItem,
                                 completion: (([String]) -> Void)?, postNotification: Bool = true,
                                 engineVersion: String? = nil) {
        progress.cancel()
        let started = operationStartTimes.removeValue(forKey: id) ?? ProcessInfo.processInfo.systemUptime
        let notify = postNotification && OperationFeedbackPolicy.shouldNotify(
            elapsed: ProcessInfo.processInfo.systemUptime - started, applicationActive: NSApp.isActive)
        activeOperations.removeValue(forKey: id)
        progressOperations.remove(id)
        refreshOperationState()
        let status = explicitStatus ?? (outputs.isEmpty ? .failed : (failures.isEmpty ? .completed : .partial))
        let detail = explicitDetail ?? (outputs.isEmpty
            ? (failures.first?.message ?? text("No files were created."))
            : (language == "ru"
                ? "сохранено файлов: \(outputs.count) · ошибок: \(failures.count)"
                : "saved files: \(outputs.count) · failed: \(failures.count)"))
        recordOperation(id: id, action: action, files: files, outputs: outputs.map(\.path),
                        failures: failures, status: status, detail: detail, postNotification: notify,
                        engineVersion: engineVersion)
        completion?(outputs.map(\.path))
    }

    func updateNotificationPermission(_ permission: NotificationPermission) {
        let key: String
        switch permission {
        case .authorized, .provisional, .ephemeral: key = "Allowed"
        case .notDetermined: key = "Not requested"
        case .denied: key = "Denied"
        }
        notificationPermission = text(key)
    }

    func updateNotificationResult(_ delivery: NotificationDelivery, operationID: UUID? = nil) {
        let result: String
        switch delivery {
        case .transmitted: result = text("Transmitted to macOS")
        case .permissionRequired: result = text("Permission is required")
        case .denied: result = text("Denied")
        case .failed(let detail):
            let safe = EngineClient.safeDetail(detail)
            result = safe.isEmpty ? text("Sending failed") : "\(text("Sending failed")): \(safe)"
        }
        notificationLastResult = result
        guard let operationID, let index = recent.firstIndex(where: { $0.id == operationID }) else { return }
        recent[index].notificationDelivery = result
        persistRecentOperations()
    }

    func testNotification() { Task { @MainActor [weak self] in self?.delegate?.testNotification() } }
    func openNotificationSettings() { Task { @MainActor [weak self] in self?.delegate?.openNotificationSettings() } }

    private func writeDiagnostic(operationID: UUID, engineVersion: String?, stage: String,
                                 code: String, detail: String) {
        let base = MultiAuditEnvironment.root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MultiShift", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let url = base.appendingPathComponent("diagnostics.jsonl")
            let record: [String: String] = ["operation_id": operationID.uuidString,
                                            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                                            "engine_version": engineVersion ?? "unknown", "stage": stage, "code": code,
                                            "detail": EngineClient.safeDetail(detail)]
            let line = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) + Data([0x0A])
            var existing = (try? Data(contentsOf: url)) ?? Data()
            if existing.count > 512 * 1024 { existing = Data(existing.suffix(256 * 1024)) }
            existing.append(line)
            try existing.write(to: url, options: .atomic)
        } catch { NSLog("MultiShift could not write diagnostics") }
    }

    func undoOperation(id: UUID) {
        guard let index = recent.firstIndex(where: { $0.id == id }), recent[index].canUndo else { return }
        var failed = 0
        var retryable: [OutputFingerprint] = []
        for fingerprint in recent[index].outputFingerprints {
            guard fingerprint.stillMatches() else { failed += 1; continue }
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: fingerprint.path), resultingItemURL: nil)
            } catch {
                failed += 1
                if fingerprint.stillMatches() { retryable.append(fingerprint) }
            }
        }
        recent[index].date = Date()
        recent[index].status = failed == 0 ? .undone : .undoFailed
        recent[index].title = text(failed == 0 ? "Undone" : "Undo failed")
        recent[index].detail = failed == 0
            ? text("Output files moved to Trash.")
            : text("Some output files changed and were left untouched.")
        if failed == 0 {
            recent[index].outputPaths = []
            recent[index].outputFingerprints = []
        } else {
            recent[index].outputPaths = retryable.map(\.path)
            recent[index].outputFingerprints = retryable
        }
        persistRecentOperations()
        let updatedOperation = recent[index]
        Task { @MainActor [weak self] in self?.delegate?.operationDidUpdate(updatedOperation, postNotification: false) }
    }

    func operation(id: UUID) -> RecentOperation? { recent.first { $0.id == id } }

    func showError(title: String, detail: String) {
        Task { @MainActor [weak self] in self?.delegate?.showError(title: title, detail: detail) }
    }

    private func refreshOperationState() {
        busyFiles = Array(Set(activeOperations.values.flatMap { $0.map(\.path) })).sorted()
        longRunningOperationCount = progressOperations.count
    }

    private func recordOperation(id: UUID, action: String, files: [URL], outputs: [String],
                                 failures: [OperationFailure], status: OperationStatus, detail: String,
                                 postNotification: Bool, engineVersion: String? = nil) {
        let fingerprints = outputs.compactMap(OutputFingerprint.capture)
        let safeFingerprints = fingerprints.count == outputs.count ? fingerprints : []
        let titleKey: String
        switch status {
        case .completed: titleKey = "Completed"
        case .partial: titleKey = "Partial result"
        case .failed, .undoFailed: titleKey = "Failed"
        case .cancelled: titleKey = "Cancelled"
        case .undone: titleKey = "Undone"
        case .running: titleKey = "Working…"
        }
        let operation = RecentOperation(id: id, actionTitle: displayName(for: action), title: text(titleKey),
                                        detail: detail, inputNames: files.map(\.lastPathComponent),
                                        outputPaths: outputs, outputFingerprints: safeFingerprints,
                                        date: Date(), status: status, failureCount: failures.count,
                                        failures: failures, notificationDelivery: nil,
                                        engineVersion: engineVersion)
        if let index = recent.firstIndex(where: { $0.id == id }) { recent[index] = operation }
        else { recent.insert(operation, at: 0) }
        recent = Array(recent.prefix(20))
        persistRecentOperations()
        if status != .running, status != .cancelled {
            for failure in failures {
                writeDiagnostic(operationID: id, engineVersion: engineVersion, stage: failure.stage,
                                code: failure.code, detail: failure.message)
            }
        }
        Task { @MainActor [weak self] in self?.delegate?.operationDidUpdate(operation, postNotification: postNotification) }
    }

    private func displayName(for action: String) -> String {
        let key = action.replacingOccurrences(of: "convert:", with: "")
            .replacingOccurrences(of: "tool:", with: "")
        return text(key)
    }

    @MainActor func deleteHistoryEntry(id: UUID) throws {
        guard let entry = recent.first(where: { $0.id == id }), entry.canDeleteFromHistory else { return }
        let remaining = recent.filter { $0.id != id }
        let url = Self.operationsURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(remaining).write(to: url, options: .atomic)
        recent = remaining
        delegate?.refreshStatusMenu()
    }

    private func persistRecentOperations() {
        Self.saveOperations(recent)
        Task { @MainActor [weak self] in self?.delegate?.refreshStatusMenu() }
    }

    private static var operationsURL: URL {
        if let root = MultiAuditEnvironment.root {
            return root.appendingPathComponent("operations.json")
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("MultiShift", isDirectory: true).appendingPathComponent("operations.json")
    }

    private static func loadOperations() -> [RecentOperation] {
        guard let data = try? Data(contentsOf: operationsURL),
              let operations = try? JSONDecoder().decode([RecentOperation].self, from: data) else { return [] }
        return Array(operations.prefix(20))
    }

    private static func saveOperations(_ operations: [RecentOperation]) {
        let directory = operationsURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Array(operations.prefix(20)))
            try data.write(to: operationsURL, options: .atomic)
        } catch {
            NSLog("MultiShift could not save operation history: %@", error.localizedDescription)
        }
    }

    func setLoginItem(_ enabled: Bool) {
        guard MultiAuditEnvironment.root == nil else { return }
        let legacyAgent = Self.legacyAgentURL
        if enabled {
            do {
                if #available(macOS 13.0, *) { try SMAppService.mainApp.register() }
                if FileManager.default.fileExists(atPath: legacyAgent.path) {
                    Self.unloadLegacyAgent(legacyAgent)
                    try? FileManager.default.removeItem(at: legacyAgent)
                }
                loginEnabled = true
            } catch {
                loginEnabled = Self.hasLegacyLoginAgent()
                showError(title: text("Couldn't finish"), detail: error.localizedDescription)
            }
        } else {
            if #available(macOS 13.0, *) { try? SMAppService.mainApp.unregister() }
            if FileManager.default.fileExists(atPath: legacyAgent.path) {
                Self.unloadLegacyAgent(legacyAgent)
                try? FileManager.default.removeItem(at: legacyAgent)
            }
            loginEnabled = false
        }
    }

    private static let legacyAgentURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.multiswitcher.multishift.plist")

    private static func hasLegacyLoginAgent() -> Bool {
        FileManager.default.fileExists(atPath: legacyAgentURL.path)
    }

    private static func unloadLegacyAgent(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())", url.path]
        try? process.run()
        process.waitUntilExit()
    }

    private static func migrateOldSettings() {
        guard MultiAuditEnvironment.root == nil else { return }
        guard !defaults.bool(forKey: "legacySettingsMigrated") else { return }
        let source = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.multishift.MultiShift.plist")
        if let data = try? Data(contentsOf: source),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for key in settingsKeys where defaults.object(forKey: key) == nil {
                if let value = plist[key] { defaults.set(value, forKey: key) }
            }
        }
        defaults.set(true, forKey: "legacySettingsMigrated")
    }

    private static func formatHint(_ target: String, language: String) -> String {
        guard language == "ru" else {
            return (["PNG": "Lossless · transparency", "JPG": "Small · universal", "WEBP": "Compact for web", "PDF": "Document"][target] ?? "Create \(target) copy").lowercased()
        }
        return (["PNG": "Без потерь · прозрачность", "JPG": "Компактный универсальный", "WEBP": "Для веба", "PDF": "Документ"][target] ?? "Создать копию \(target)").lowercased()
    }

    private static func toolHint(_ key: String, language: String) -> String {
        let hints = language == "ru"
            ? ["Compress": "Уменьшить размер", "Resize": "Изменить размеры", "Crop": "Обрезать кадр", "Edit": "Настроить изображение", "Annotate": "Добавить разметку", "Redact": "Скрыть личные данные", "Add BG": "Добавить фон", "Metadata": "Посмотреть или удалить данные", "Split": "По странице в файл", "Rotate": "Повернуть страницы", "Merge": "Объединить PDF", "Protect": "Добавить пароль", "Extract": "Извлечь изображения"]
            : ["Compress": "Reduce file size", "Resize": "Change dimensions", "Crop": "Trim the image", "Edit": "Adjust the image", "Annotate": "Add markup", "Redact": "Hide private data", "Add BG": "Add a backdrop", "Metadata": "View or remove data", "Split": "One page per file", "Rotate": "Rotate pages", "Merge": "Join PDF files", "Protect": "Add a password", "Extract": "Extract images"]
        return (hints[key] ?? "").lowercased()
    }
}
