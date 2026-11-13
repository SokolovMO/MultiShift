import AppKit
import SwiftUI
import AVKit

private struct EditorMark: Equatable {
    var kind: String
    var points: [CGPoint]
    var color: String
    var width: Double
    var text: String
}

private struct EditorDraft: Equatable {
    var brightness = 1.0, contrast = 1.0, saturation = 1.0, warmth = 0.0, sharpness = 1.0
    var rotation = 0
    var flipH = false, flipV = false, grayscale = false, auto = false
    var quality = 72.0, targetKB = 500.0
    var targetSize = false
    var maxSide = 0
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    var cropRatio = 0.0
    var resizeMode = "pct", resizeValue = 50.0, width = 1920.0, height = 1080.0
    var proportions = true
    var background = "soft", padding = 0.12, radius = 24.0
    var metadataMode = "strip"
    var marks: [EditorMark] = []
    var start = 0.0, end = 0.0, speed = 1.0, gain = 0.0, fadeIn = 0.0, fadeOut = 0.0
    var normalize = false, mono = false, mute = false, fastCut = false, hevc = false
    var kbps = 128, mediaHeight = 0, preset = "Balanced"
}

struct NativeFileEditor: View {
    @ObservedObject var model: AppModel
    let files: [URL]
    let action: ActionItem
    let close: () -> Void
    @State private var draft = EditorDraft()
    @State private var original: NSImage?
    @State private var rendered: NSImage?
    @State private var sourceWidth = 1
    @State private var sourceHeight = 1
    @State private var metadata: [String: String] = [:]
    @State private var summary: [String: String] = [:]
    @State private var status = ""
    @State private var error: String?
    @State private var busy = false
    @State private var rendering = false
    @State private var compare = false
    @State private var renderWork: DispatchWorkItem?
    @State private var revision = 0
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var markKind = "arrow"
    @State private var markText = ""
    @State private var markColor = Color.red
    @State private var markWidth = 4.0
    @State private var redoMarks: [EditorMark] = []
    @State private var gesturePoints: [CGPoint] = []
    @State private var duration = 0.0
    @State private var player: AVPlayer?
    @State private var sourceScope = false
    @State private var saved = false
    @State private var operationID: UUID?
    @State private var sampleURL: URL?
    @State private var fitPreview = true
    private var tool: String { action.id.replacingOccurrences(of: "tool:", with: "") }
    private var media: Bool { files.first.map(ExtendedFormats.isMedia) ?? false }
    private var audio: Bool { files.first.map { ExtendedFormats.audio.contains($0.pathExtension.lowercased()) } ?? false }
    private var image: Bool { files.first.map(ExtendedFormats.isImage) ?? false }
    private var ru: Bool { model.language == "ru" }
    private func t(_ ru: String, _ en: String) -> String { self.ru ? ru : en }
    private var pixelWidth: Int { tool == "Crop" && draft.rotation % 180 != 0 ? sourceHeight : sourceWidth }
    private var pixelHeight: Int { tool == "Crop" && draft.rotation % 180 != 0 ? sourceWidth : sourceHeight }
    private var canSave: Bool {
        if busy || original == nil { return false }
        if tool == "Protect" { return password.count >= 4 && password == confirmPassword }
        if tool == "Annotate" || tool == "Redact" { return !draft.marks.isEmpty }
        if tool == "Trim" { return draft.end > draft.start && draft.start >= 0 && draft.end <= duration + 0.05 }
        return true
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title).font(.title2)
                    Text(files.first?.lastPathComponent ?? "").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if files.count > 1 { Text(t("Файлов: \(files.count)", "Files: \(files.count)")) }
            }.padding(20)
            Divider()
            HSplitView {
                preview.frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                Form { controls }.formStyle(.grouped).frame(minWidth: 300, idealWidth: 320, maxWidth: 360)
            }
            Divider()
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled).padding(.horizontal, 20).padding(.top, 8) }
            if saved, let operationID, let operation = model.operation(id: operationID) { OperationFeedbackStrip(model: model, operation: operation).padding(.horizontal, 16) }
            HStack {
                if busy || rendering { ProgressView().controlSize(.small) }
                Text(busy ? t("Обработка…", "Processing…") : status.isEmpty ? t("Сохраняется новая копия. Оригиналы сохраняются.", "Saves a new copy. Originals are preserved.") : status)
                    .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button(saved ? t("Закрыть", "Close") : model.text("Cancel"), action: close).keyboardShortcut(.cancelAction).disabled(busy)
                Button(model.text("Save Copy"), action: save).keyboardShortcut(.defaultAction).disabled(!canSave)
            }.padding(16)
        }
        .frame(minWidth: 820, minHeight: 540)
        .onAppear(perform: load)
        .onDisappear { renderWork?.cancel(); player?.pause(); if let sampleURL { try? FileManager.default.removeItem(at: sampleURL) }; if sourceScope, let first = files.first { first.stopAccessingSecurityScopedResource() } }
        .onChange(of: draft) { _, _ in scheduleRender() }
        .onChange(of: fitPreview) { _, _ in reloadOriginal() }
    }

    private var preview: some View {
        VStack(spacing: 0) {
            HStack {
                Text(t("Предпросмотр", "Preview")).font(.headline)
                Spacer()
                if image && tool != "Crop" && tool != "Metadata" {
                    Toggle(t("Оригинал", "Original"), isOn: $compare).toggleStyle(.button)
                }
                if image {
                    Picker(t("Масштаб", "Zoom"), selection: $fitPreview) {
                        Text(t("Вписать", "Fit")).tag(true)
                        Text("100%").tag(false)
                    }.pickerStyle(.segmented).frame(width: 130)
                }
                if image { Text("\(pixelWidth) × \(pixelHeight)").monospacedDigit().foregroundStyle(.secondary) }
            }.padding(12)
            Divider()
            if media, let player {
                VideoPlayer(player: player).frame(minHeight: 200)
                if tool == "Trim" {
                    HStack {
                        Button(t("К началу фрагмента", "Go to start")) { player.seek(to: CMTime(seconds: draft.start, preferredTimescale: 600)) }
                        Button(t("К концу фрагмента", "Go to end")) { player.seek(to: CMTime(seconds: draft.end, preferredTimescale: 600)) }
                    }.padding(8)
                }
            }
            if !media || audio {
                GeometryReader { geometry in
                    let available = CGSize(width: max(1, geometry.size.width - 24), height: max(1, geometry.size.height - 24))
                    let displayed = compare ? original : (rendered ?? original)
                    if let displayed {
                        let ratio = fitPreview ? min(available.width / max(1, displayed.size.width), available.height / max(1, displayed.size.height)) : 1
                        let size = CGSize(width: displayed.size.width * ratio, height: displayed.size.height * ratio)
                        ScrollView([.horizontal, .vertical]) {
                        ZStack {
                            Image(nsImage: displayed).resizable().interpolation(.high)
                            if tool == "Crop" { cropOverlay(size) }
                            if gesturePoints.count > 1, tool == "Annotate" || tool == "Redact" {
                                Path { path in
                                    path.move(to: CGPoint(x: gesturePoints[0].x * size.width, y: gesturePoints[0].y * size.height))
                                    for p in gesturePoints.dropFirst() { path.addLine(to: CGPoint(x: p.x * size.width, y: p.y * size.height)) }
                                }.stroke(Color.accentColor, lineWidth: 2)
                            }
                        }
                        .frame(width: size.width, height: size.height)
                        .contentShape(Rectangle())
                        .gesture(canvasGesture(size))
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                        }
                    } else { ProgressView().position(x: geometry.size.width / 2, y: geometry.size.height / 2) }
                }.background(Color(nsColor: .underPageBackgroundColor))
            }
        }
    }
    private func cropOverlay(_ size: CGSize) -> some View {
        let rect = CGRect(x: draft.crop.minX * size.width, y: draft.crop.minY * size.height, width: draft.crop.width * size.width, height: draft.crop.height * size.height)
        return ZStack(alignment: .topLeading) {
            Path { path in path.addRect(CGRect(origin: .zero, size: size)); path.addRect(rect) }.fill(.black.opacity(0.4), style: FillStyle(eoFill: true))
            Rectangle().stroke(.white, lineWidth: 1).frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
        }.allowsHitTesting(false)
    }

    @ViewBuilder private var controls: some View {
        if media {
            mediaControls
            Section(t("Проверка результата", "Result preview")) {
                Button(t("Предпросмотр 5 секунд", "Preview 5 seconds"), action: renderMedia).disabled(rendering || busy || original == nil)
                Button(t("Воспроизвести оригинал", "Play original")) {
                    if let first = files.first { player?.replaceCurrentItem(with: AVPlayerItem(url: first)); player?.play() }
                }
                Text(t("Плеер сначала показывает оригинал. Предпросмотр применяет настройки к короткому фрагменту. Вес медиа — оценка.", "The player initially shows the original. Preview applies settings to a short clip. Media size is an estimate.")).foregroundStyle(.secondary)
            }
        }
        else {
            switch tool {
            case "Crop": cropControls
            case "Annotate", "Redact": markControls
            case "Edit": adjustmentControls
            case "Compress": compressControls
            case "Resize": resizeControls
            case "Add BG": backgroundControls
            case "Metadata": metadataControls
            case "Protect":
                Section(t("Защита PDF", "PDF protection")) {
                    SecureField(t("Пароль", "Password"), text: $password)
                    SecureField(t("Повтор пароля", "Confirm password"), text: $confirmPassword)
                    Text(t("Не менее 4 символов. Шифрование AES-256.", "At least 4 characters. AES-256 encryption.")).foregroundStyle(.secondary)
                    if !confirmPassword.isEmpty && password != confirmPassword { Text(t("Пароли не совпадают", "Passwords do not match")).foregroundStyle(.red) }
                }
            default: EmptyView()
            }
        }
    }
    private var adjustmentControls: some View {
        Group {
            Section(t("Коррекция", "Adjustments")) {
                Toggle(t("Автокоррекция", "Auto enhance"), isOn: $draft.auto)
                valueSlider(t("Яркость", "Brightness"), $draft.brightness, 0.5...1.5)
                valueSlider(t("Контраст", "Contrast"), $draft.contrast, 0.5...1.5)
                valueSlider(t("Насыщенность", "Saturation"), $draft.saturation, 0...2)
                valueSlider(t("Теплота", "Warmth"), $draft.warmth, -1...1)
                valueSlider(t("Резкость", "Sharpness"), $draft.sharpness, 0...2)
                Toggle(t("Чёрно-белое", "Black and white"), isOn: $draft.grayscale)
            }
            transformControls
            Section { Button(t("Сбросить коррекцию", "Reset adjustments")) { draft = EditorDraft() } }
        }
    }
    private var transformControls: some View {
        Section(t("Ориентация", "Orientation")) {
            Picker(t("Поворот", "Rotation"), selection: $draft.rotation) {
                ForEach([0, 90, 180, 270], id: \.self) { Text("\($0)°").tag($0) }
            }
            Toggle(t("Отразить по горизонтали", "Flip horizontally"), isOn: $draft.flipH)
            Toggle(t("Отразить по вертикали", "Flip vertically"), isOn: $draft.flipV)
        }
    }
    private var cropControls: some View {
        Section(t("Область обрезки", "Crop region")) {
            Text(t("Выделите область на изображении или задайте размеры в пикселях.", "Drag a region or enter pixel dimensions.")).foregroundStyle(.secondary)
            Picker(t("Пропорции", "Aspect ratio"), selection: $draft.cropRatio) {
                Text(t("Свободно", "Free")).tag(0.0); Text("1:1").tag(1.0); Text("4:3").tag(4.0/3); Text("3:2").tag(1.5); Text("16:9").tag(16.0/9); Text("9:16").tag(9.0/16)
            }
            cropField("X", axis: 0); cropField("Y", axis: 1)
            cropField(t("Ширина", "Width"), axis: 2); cropField(t("Высота", "Height"), axis: 3)
            Picker(t("Поворот", "Rotation"), selection: $draft.rotation) { ForEach([0,90,180,270], id: \.self) { Text("\($0)°").tag($0) } }
            Button(t("Выделить всё", "Select all")) { draft.crop = CGRect(x: 0, y: 0, width: 1, height: 1) }
        }
    }
    private func cropField(_ title: String, axis: Int) -> some View {
        TextField(title, value: Binding(get: {
            let r = draft.crop
            return [r.minX * Double(pixelWidth), r.minY * Double(pixelHeight), r.width * Double(pixelWidth), r.height * Double(pixelHeight)][axis]
        }, set: { value in
            var r = draft.crop
            let v = max(0, value) / Double(axis % 2 == 0 ? pixelWidth : pixelHeight)
            switch axis {
            case 0: r.origin.x = min(v, 1-r.width)
            case 1: r.origin.y = min(v, 1-r.height)
            case 2: r.size.width = max(1/Double(pixelWidth), min(v, 1-r.minX))
            default: r.size.height = max(1/Double(pixelHeight), min(v, 1-r.minY))
            }
            if draft.cropRatio > 0 {
                if axis == 2 { r.size.height = min(1-r.minY, r.width * Double(pixelWidth) / Double(pixelHeight) / draft.cropRatio) }
                if axis == 3 { r.size.width = min(1-r.minX, r.height * Double(pixelHeight) / Double(pixelWidth) * draft.cropRatio) }
            }
            draft.crop = r
        }), format: .number.precision(.fractionLength(0)))
    }
    private var markControls: some View {
        Group {
            Section(tool == "Redact" ? t("Скрытие данных", "Redaction") : t("Разметка", "Markup")) {
                if tool == "Annotate" {
                    Picker(t("Инструмент", "Tool"), selection: $markKind) {
                        Text(t("Стрелка", "Arrow")).tag("arrow"); Text(t("Рамка", "Rectangle")).tag("rect")
                        Text(t("Овал", "Ellipse")).tag("ellipse"); Text(t("Перо", "Pen")).tag("pen")
                        Text(t("Маркер", "Highlight")).tag("highlight"); Text(t("Текст", "Text")).tag("text")
                        Text(t("Номер шага", "Step number")).tag("step")
                    }
                    ColorPicker(t("Цвет", "Color"), selection: $markColor, supportsOpacity: false)
                    valueSlider(t("Толщина", "Stroke width"), $markWidth, 1...20)
                    if markKind == "text" { TextField(t("Подпись", "Label"), text: $markText) }
                }
                Text(t("Нарисуйте на изображении. Можно добавить несколько объектов.", "Draw on the image. You can add multiple objects.")).foregroundStyle(.secondary)
                if tool == "Redact" { Text(t("Области закрашиваются в новой копии. Метаданные удаляются.", "Regions are burned into a new copy. Metadata is removed.")).foregroundStyle(.secondary) }
            }
            Section {
                HStack {
                    Button(t("Отменить", "Undo"), action: undoMark).keyboardShortcut("z", modifiers: .command).disabled(draft.marks.isEmpty)
                    Button(t("Повторить", "Redo"), action: redoMark).keyboardShortcut("z", modifiers: [.command, .shift]).disabled(redoMarks.isEmpty)
                }
                Text(t("Объектов: \(draft.marks.count)", "Objects: \(draft.marks.count)"))
            }
        }
    }
    private var compressControls: some View {
        Section(t("Сжатие", "Compression")) {
            if image {
                Toggle(t("До заданного веса", "Target file size"), isOn: $draft.targetSize)
                if draft.targetSize {
                    TextField(t("Лимит, КБ", "Limit, KB"), value: $draft.targetKB, format: .number)
                    Text(t("Создаётся JPEG-копия. При необходимости уменьшается разрешение; прозрачность заменяется белым фоном.", "Creates a JPEG copy. Resolution may decrease; transparency becomes white.")).foregroundStyle(.secondary)
                } else { valueSlider(t("Качество", "Quality"), $draft.quality, 10...95) }
            } else { valueSlider(t("Качество", "Quality"), $draft.quality, 10...95) }
            Picker(t("Максимальная сторона", "Maximum side"), selection: $draft.maxSide) {
                Text(t("Без ограничения", "Original size")).tag(0)
                ForEach([3840,2560,1920,1280,800], id: \.self) { Text("\($0) px").tag($0) }
            }
            Text(t("Предпросмотр показывает фактический результат выбранных настроек.", "Preview shows the actual encoded result for these settings.")).foregroundStyle(.secondary)
        }
    }
    private var resizeControls: some View {
        Section(t("Размер копии", "Copy size")) {
            Picker(t("Режим", "Mode"), selection: $draft.resizeMode) {
                Text(t("Процент", "Percent")).tag("pct"); Text(t("Длинная сторона", "Longest side")).tag("long"); Text(t("Точный размер", "Exact dimensions")).tag("exact")
            }
            if draft.resizeMode == "exact" {
                TextField(t("Ширина, px", "Width, px"), value: $draft.width, format: .number)
                TextField(t("Высота, px", "Height, px"), value: $draft.height, format: .number)
                Toggle(t("Сохранить пропорции", "Keep proportions"), isOn: $draft.proportions)
            } else { TextField(draft.resizeMode == "pct" ? "%" : "px", value: $draft.resizeValue, format: .number) }
        }
    }
    private var backgroundControls: some View {
        Section(t("Фон", "Background")) {
            Picker(t("Оформление", "Style"), selection: $draft.background) { Text(t("Светлый", "Light")).tag("soft"); Text(t("Графит", "Graphite")).tag("graphite") }
            valueSlider(t("Поля", "Padding"), $draft.padding, 0...0.4)
            valueSlider(t("Скругление", "Corner radius"), $draft.radius, 0...100)
        }
    }
    private var metadataControls: some View {
        Group {
            Section(t("Метаданные", "Metadata")) {
                if metadata.isEmpty { Text(t("Метаданные не найдены", "No metadata found")).foregroundStyle(.secondary) }
                ForEach(metadata.keys.sorted(), id: \.self) { key in
                    LabeledContent(key) { Text(metadata[key] ?? "").textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                }
                if let location = summary["Location"] {
                    Text(t("Фото содержит координаты места съёмки.", "This photo contains location coordinates."))
                    Button(t("Открыть на карте", "Open map")) {
                        let coordinates = location.components(separatedBy: ", ")
                        if coordinates.count == 2, let url = URL(string: "https://www.openstreetmap.org/?mlat=\(coordinates[0])&mlon=\(coordinates[1])#map=15/\(coordinates[0])/\(coordinates[1])") { NSWorkspace.shared.open(url) }
                    }
                }
            }
            if !media {
                Section {
                    Picker(t("Удалить", "Remove"), selection: $draft.metadataMode) {
                        Text(t("Все метаданные", "All metadata")).tag("strip")
                        if summary["Location"] != nil || metadata.keys.contains(where: { $0.localizedCaseInsensitiveContains("gps") }) { Text(t("Только геопозицию", "Location only")).tag("location") }
                    }
                }
            }
        }
    }
    @ViewBuilder private var mediaControls: some View {
        switch tool {
        case "Trim":
            Section(t("Фрагмент", "Clip range")) {
                Text(t("Длительность: \(duration.formatted()) с", "Duration: \(duration.formatted()) s"))
                TextField(t("Начало, с", "Start, s"), value: $draft.start, format: .number)
                Slider(value: $draft.start, in: 0...max(1, duration))
                TextField(t("Конец, с", "End, s"), value: $draft.end, format: .number)
                Slider(value: $draft.end, in: 0...max(1, duration))
                if !audio { Toggle(t("Быстро, по ключевым кадрам", "Fast cut on keyframes"), isOn: $draft.fastCut) }
            }
        case "Compress":
            Section(t("Сжатие медиа", "Media compression")) {
                Toggle(t("Целевой вес (оценка)", "Target size (estimate)"), isOn: $draft.targetSize)
                if draft.targetSize { TextField(t("Лимит, КБ", "Limit, KB"), value: $draft.targetKB, format: .number) }
                if audio {
                    Picker(t("Битрейт", "Bitrate"), selection: $draft.kbps) { ForEach([64,96,128,192,256], id: \.self) { Text("\($0) kbps").tag($0) } }
                    Toggle(t("Моно", "Mono"), isOn: $draft.mono)
                } else {
                    Picker(t("Качество", "Quality"), selection: $draft.preset) { Text(t("Высокое", "High")).tag("High"); Text(t("Сбалансированное", "Balanced")).tag("Balanced"); Text(t("Компактное", "Small")).tag("Small") }
                    mediaResolution
                    Toggle("H.265 / HEVC", isOn: $draft.hevc)
                }
            }
        case "Edit":
            Section(t("Звук и скорость", "Audio and speed")) {
                valueSlider(t("Громкость, дБ", "Gain, dB"), $draft.gain, -24...24)
                valueSlider(t("Скорость", "Speed"), $draft.speed, 0.25...4)
                Toggle(t("Выровнять громкость", "Normalize loudness"), isOn: $draft.normalize)
                if audio {
                    Toggle(t("Моно", "Mono"), isOn: $draft.mono)
                    TextField(t("Нарастание, с", "Fade in, s"), value: $draft.fadeIn, format: .number)
                    TextField(t("Затухание, с", "Fade out, s"), value: $draft.fadeOut, format: .number)
                } else { Toggle(t("Удалить звук", "Remove audio"), isOn: $draft.mute) }
            }
            if !audio { transformControls; Section { mediaResolution } }
        case "Metadata": metadataControls
        default: EmptyView()
        }
    }
    private var mediaResolution: some View {
        Picker(t("Высота видео", "Video height"), selection: $draft.mediaHeight) {
            Text(t("Исходная", "Original")).tag(0)
            ForEach([2160,1080,720,480], id: \.self) { Text("\($0)p").tag($0) }
        }
    }
    private func valueSlider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2)))).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }

    private func canvasGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { value in
            guard ["Crop", "Annotate", "Redact"].contains(tool) else { return }
            func normalized(_ p: CGPoint) -> CGPoint { CGPoint(x: min(1, max(0, p.x / max(1,size.width))), y: min(1, max(0,p.y / max(1,size.height)))) }
            let start = normalized(value.startLocation), end = normalized(value.location)
            if gesturePoints.isEmpty { gesturePoints = [start] }
            if markKind == "pen" || markKind == "highlight" { gesturePoints.append(end) } else { gesturePoints = [start, end] }
            if tool == "Crop" {
                let x = min(start.x,end.x), y = min(start.y,end.y)
                var w = max(1/Double(pixelWidth), abs(end.x-start.x)), h = max(1/Double(pixelHeight),abs(end.y-start.y))
                if draft.cropRatio > 0 { h = w * Double(pixelWidth) / Double(pixelHeight) / draft.cropRatio; if h > 1-y { h = 1-y; w = h * Double(pixelHeight) / Double(pixelWidth) * draft.cropRatio } }
                draft.crop = CGRect(x: x, y: y, width: min(w,1-x), height: min(h,1-y))
            }
        }.onEnded { _ in
            defer { gesturePoints = [] }
            guard tool == "Annotate" || tool == "Redact", !gesturePoints.isEmpty else { return }
            let color = NSColor(markColor).usingColorSpace(.sRGB) ?? .red
            let hex = String(format: "#%02x%02x%02x", Int(color.redComponent*255),Int(color.greenComponent*255),Int(color.blueComponent*255))
            let text = markKind == "step" ? String(draft.marks.filter { $0.kind == "step" }.count + 1) : markText
            if markKind == "text" && text.isEmpty { return }
            draft.marks.append(EditorMark(kind: tool == "Redact" ? "redact" : markKind, points: gesturePoints, color: tool == "Redact" ? "#000000" : hex, width: markWidth, text: text))
            redoMarks = []
        }
    }
    private func undoMark() { if let item = draft.marks.popLast() { redoMarks.append(item) } }
    private func redoMark() { if let item = redoMarks.popLast() { draft.marks.append(item) } }
    private func parameters() -> [String: Any] {
        var p: [String: Any] = [:]
        if media {
            p = ["start": draft.start, "end": draft.end, "speed": draft.speed, "gain_db": draft.gain,
                 "fade_in": max(0,draft.fadeIn), "fade_out": max(0,draft.fadeOut), "normalize": draft.normalize, "mono": draft.mono,
                 "mute": draft.mute, "fast_cut": draft.fastCut, "rotate": draft.rotation, "flip_h": draft.flipH, "flip_v": draft.flipV,
                 "kbps": draft.kbps, "height": draft.mediaHeight, "preset": draft.preset, "hevc": draft.hevc]
            if draft.targetSize { p["target_bytes"] = max(1024,Int(draft.targetKB*1000)) }
            return p
        }
        switch tool {
        case "Crop": p = ["x": Int(draft.crop.minX * Double(pixelWidth)), "y": Int(draft.crop.minY * Double(pixelHeight)), "width": max(1,Int(draft.crop.width * Double(pixelWidth))), "height": max(1,Int(draft.crop.height * Double(pixelHeight))), "rotate": draft.rotation]
        case "Edit": p = ["brightness": draft.brightness, "contrast": draft.contrast, "saturation": draft.saturation, "warmth": draft.warmth, "sharpness": draft.sharpness, "rotate": draft.rotation, "flip_h": draft.flipH, "flip_v": draft.flipV, "grayscale": draft.grayscale, "auto": draft.auto]
        case "Compress":
            p = ["quality": Int(draft.quality), "max_side": draft.maxSide]
            if draft.targetSize { p["target_bytes"] = max(1024,Int(draft.targetKB*1000)) }
        case "Resize": p = ["mode": draft.resizeMode, "value": max(1, Int(draft.resizeValue)), "width": max(1,Int(draft.width)), "height": max(1,Int(draft.height)), "keep_proportions": draft.proportions]
        case "Add BG": p = ["colors": draft.background == "soft" ? ["#E9E9EB","#BFC0C4"] : ["#55565A","#252629"], "padding": draft.padding, "radius": Int(draft.radius), "shadow": 0.35]
        case "Metadata": p = ["mode": draft.metadataMode]
        case "Protect": p = ["password": password]
        case "Annotate", "Redact":
            let items: [[String: Any]] = draft.marks.map { mark in
                let points = mark.points.map { [Int($0.x * Double(sourceWidth)), Int($0.y * Double(sourceHeight))] }
                let first = points.first ?? [0,0], last = points.last ?? first
                let box = mark.kind == "arrow" ? first + last : [min(first[0],last[0]),min(first[1],last[1]),max(first[0],last[0])+1,max(first[1],last[1])+1]
                return ["kind": mark.kind, "box": box, "points": points, "color": mark.color, "width": Int(mark.width), "text": mark.text]
            }
            p = tool == "Redact" ? ["rects": items.compactMap { $0["box"] as? [Int] }, "mode": "black"] : ["items": items]
        default: break
        }
        return p
    }
    private func load() {
        guard let url = files.first else { return }
        model.preview(url: url) { info, fields, detail in
            metadata = fields; error = detail
            if let info {
                original = NSImage(contentsOf: info.url); sourceWidth = info.sourceWidth; sourceHeight = info.sourceHeight
                try? FileManager.default.removeItem(at: info.url)
                scheduleRender()
            }
        }
        model.inspectCopy(url, request: ["operation": "inspect"]) { response, _ in
            summary = response?["summary"] as? [String: String] ?? [:]
        }
        if media {
            sourceScope = url.startAccessingSecurityScopedResource()
            player = AVPlayer(url: url)
            model.inspectCopy(url, request: ["operation": "media_info"]) { response, detail in
                duration = response?["duration"] as? Double ?? 0; draft.end = duration
                if let detail { error = detail }
            }
        }
    }
    private func reloadOriginal() {
        guard let url = files.first, image else { return }
        model.preview(url: url, maxSide: fitPreview ? 1800 : 4096) { info, _, detail in
            if let info {
                original = NSImage(contentsOf: info.url)
                try? FileManager.default.removeItem(at: info.url)
                scheduleRender()
            } else { error = detail }
        }
    }
    private func scheduleRender() {
        renderWork?.cancel(); revision += 1
        guard image, original != nil, !["Metadata", "Protect"].contains(tool) else { return }
        let work = DispatchWorkItem { render() }; renderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    private func render() {
        guard !rendering, let url = files.first else { return }
        let currentRevision = revision
        rendering = true
        var p = parameters(), renderAction = action.id
        if tool == "Crop" { p = ["rotate": draft.rotation]; renderAction = "tool:Edit" }
        if (tool == "Annotate" || tool == "Redact") && draft.marks.isEmpty { rendered = nil; rendering = false; return }
        model.inspectCopy(url, request: ["operation": "render", "action": renderAction, "parameters": p, "max_side": fitPreview ? 1800 : 4096]) { response, detail in
            rendering = false
            if let preview = response?["preview"] as? [String: Any], let path = preview["path"] as? String {
                let result = NSImage(contentsOfFile: path)
                try? FileManager.default.removeItem(atPath: path)
                if currentRevision == revision { rendered = result; status = OperationSummary.describe(response?["metrics"] as? [String: Any] ?? [:], language: model.language); error = nil }
            } else if currentRevision == revision { error = detail }
            if currentRevision != revision { render() }
        }
    }
    private func renderMedia() {
        guard let url = files.first else { return }
        rendering = true; error = nil
        model.inspectCopy(url, request: ["operation": "media_render", "action": action.id, "parameters": parameters()]) { response, detail in
            rendering = false
            if let path = response?["media_preview"] as? String {
                if let sampleURL { try? FileManager.default.removeItem(at: sampleURL) }
                sampleURL = URL(fileURLWithPath: path)
                player?.replaceCurrentItem(with: AVPlayerItem(url: sampleURL!)); player?.play()
                if let bytes = response?["estimated_bytes"] as? Int64 { status = t("Оценка полного файла: ", "Estimated full file: ") + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
            } else { error = detail }
        }
    }
    private func save() {
        busy = true; saved = false; error = nil; player?.pause()
        operationID = model.perform(action: action.id, files: files, parameters: parameters()) { outputs in
            busy = false; saved = !outputs.isEmpty
            if outputs.isEmpty { error = operationID.flatMap { model.operation(id: $0) }?.failures?.first?.message ?? t("Копия не создана. Проверьте историю операции.", "No copy was created. Check operation history.") }
        }
    }
}
