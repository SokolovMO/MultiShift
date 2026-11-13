import AppKit
import SwiftUI

private let graphite = Mono.ink
private let secondaryInk = Mono.secondary
private let separator = Mono.line

struct WelcomeView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var demoStage = 0
    let close: () -> Void
    let settings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                AppMark(size: 40)
                VStack(alignment: .leading, spacing: 8) {
                Text(model.text("Welcome to MultiShift"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(graphite)
                Text(model.text("Move files through a faster workflow."))
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryInk)
            }
                }
            HStack(alignment: .top, spacing: 12) {
                MultiInstructionCard(
                    number: "1",
                    title: model.language == "ru" ? "перетащите файл" : "drag a file",
                    detail: model.language == "ru" ? "из finder или с рабочего стола" : "from finder or the desktop",
                    symbol: "doc.on.doc",
                    iconOpacity: demoStage >= 1 ? 1 : 0.35,
                    reduceMotion: reduceMotion
                )
                MultiInstructionCard(
                    number: "2",
                    title: (model.language == "ru" ? "удерживайте " : "hold ") + (model.trigger == "ctrl" ? "control" : model.trigger == "alt" ? "option" : "shift"),
                    detail: model.language == "ru"
                        ? "откроется круговое меню. нажмите эту клавишу ещё раз, чтобы сменить режим."
                        : "the radial menu opens. press the key again to switch modes.",
                    symbol: "shift",
                    iconOpacity: demoStage >= 2 ? 1 : 0.35,
                    reduceMotion: reduceMotion,
                    keyLabel: model.trigger == "ctrl" ? "⌃" : model.trigger == "alt" ? "⌥" : "⇧"
                )
                MultiInstructionCard(
                    number: "3",
                    title: model.language == "ru" ? "выберите действие" : "choose an action",
                    detail: model.language == "ru"
                        ? "копия появится рядом, оригинал останется на месте."
                        : "a copy appears beside the original, which stays in place.",
                    symbol: "circle.grid.2x2",
                    iconOpacity: demoStage >= 3 ? 1 : 0.35,
                    reduceMotion: reduceMotion
                )
            }
            .frame(height: 180)
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button(model.text("Settings"), action: settings)
                    .buttonStyle(MonoButtonStyle())
                    .keyboardShortcut(",", modifiers: .command)
                Spacer()
                Button(model.text("Start using MultiShift"), action: close)
                    .buttonStyle(MonoButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 600, height: 340)
        .background(Mono.canvas)

        .onAppear {
            if model.welcomeDemoPlayed || reduceMotion {
                demoStage = 3
                model.markWelcomeDemoPlayed()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(Mono.animation(reduceMotion: reduceMotion)) { demoStage = 1 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                withAnimation(Mono.animation(reduceMotion: reduceMotion)) { demoStage = 2 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
                withAnimation(Mono.animation(reduceMotion: reduceMotion)) { demoStage = 3 }
                model.markWelcomeDemoPlayed()
            }
        }
    }
}


struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var section = SettingsSection.general
    @AppStorage("ecosystem.sidebarCollapsed", store: AppModel.defaults) private var sidebarCollapsed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var sidebarFocused: Bool

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case general = "General", files = "Files", appearance = "Appearance", notifications = "Notifications", about = "About"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .files: return "doc.on.doc"
            case .appearance: return "circle.lefthalf.filled"
            case .notifications: return "bell"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        MultiSidebarContainer(appName: "multishift",
            items: SettingsSection.allCases.map { MultiNavigationItem(id: $0.rawValue, title: model.text($0.rawValue), symbol: $0.symbol) },
            selected: section.rawValue, collapsed: sidebarCollapsed,
            onSelect: { if let next = SettingsSection(rawValue: $0) { section = next } }) {
            ScrollView {
                VStack(alignment: .leading, spacing: MultiInterfaceMetrics.cardSpacing) {
                    if let latest = model.recent.first {
                        OperationFeedbackStrip(model: model, operation: latest)
                    }
                    switch section {
                    case .general: general
                    case .files: files
                    case .appearance: appearance
                    case .notifications: notifications
                    case .about: about
                    }
                }
                .id(section)
                .transition(.opacity)
                .animation(MultiMotion.navigation, value: section)
                .frame(maxWidth: MultiInterfaceMetrics.settingsMaximum, alignment: .leading)
                .padding(MultiInterfaceMetrics.pageInset)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Mono.canvas)
            .coordinateSpace(name: "multi-settings")
            .onPreferenceChange(MultiSurfacePreference.self) { frames in
                Task { @MainActor in MultiSurfaceMetrics.frames = frames }
            }
        }
        .tint(Color(nsColor: MultiDesign.accent))
        .onReceive(NotificationCenter.default.publisher(for: .multiSidebarToggle)) { _ in sidebarCollapsed.toggle() }
        .onChange(of: model.language) { model.saveSettings() }
        .onChange(of: model.appearance) { model.saveSettings() }
        .onChange(of: model.trigger) { model.saveSettings() }
        .onChange(of: model.output) { model.saveSettings() }
        .onChange(of: model.jpgQuality) { model.saveSettings() }
        .onChange(of: model.pdfDPI) { model.saveSettings() }
        .onChange(of: model.loginEnabled) { _, value in model.setLoginItem(value) }
    }

    private static var architecture: String {
        #if arch(arm64)
        "Apple Silicon (arm64)"
        #else
        "Intel (x86_64)"
        #endif
    }
    private func copy(_ ru: String, _ en: String) -> String { model.language == "ru" ? ru : en }
    private func moveSidebar(_ delta: Int) {
        let all = SettingsSection.allCases
        guard let index = all.firstIndex(of: section) else { return }
        section = all[max(0, min(all.count - 1, index + delta))]
    }
    private var general: some View {
        Group {
            PaneHeading(title: model.text("General"), subtitle: copy("короткий путь от файла к результату", "a shorter path from file to result"))
            SettingsGroup {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(copy("включить multishift", "enable multishift")).font(.system(size: 12, weight: .medium))
                        Text(copy("действия с файлами прямо из finder", "file actions straight from finder")).font(.system(size: 11)).foregroundStyle(secondaryInk)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: Binding(get: { model.enabled }, set: { model.delegate?.updateEnabled($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .accessibilityLabel(copy("включить multishift", "enable multishift"))
                }
                Divider()
                SettingsRow(model.text("Open MultiShift at login"), icon: "power") {
                    Toggle("", isOn: $model.loginEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .accessibilityLabel(model.text("Open MultiShift at login"))
                }
            }
            SettingsGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Label(model.text("Open the menu with"), systemImage: "keyboard").font(.system(size: 12, weight: .medium))
                    HStack(spacing: 8) {
                        Keycap(text: model.trigger == "ctrl" ? "⌃" : model.trigger == "alt" ? "⌥" : "⇧", active: true)
                        MultiNativePopUp(title: model.text("Open the menu with"), selection: $model.trigger,
                            options: [.init("shift", "shift"), .init("control", "ctrl"), .init("option", "alt")])
                            .frame(width: 150, height: 28)
                        Spacer()
                    }
                    Text(copy("перетащите файл и удерживайте выбранную клавишу. нажмите её ещё раз, чтобы перейти к инструментам.", "drag a file and hold the selected key. press it again to switch to tools."))
                        .font(.system(size: 11)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
                }
            }
            deletionConfirmationCard
            reassurance
        }
    }
    private var files: some View {
        Group {
            PaneHeading(title: model.text("Files"), subtitle: copy("сохранение и качество готовых копий", "output location and copy quality"), symbol: "doc.on.doc")
            SettingsGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Label(model.text("Save results"), systemImage: "folder").font(.system(size: 12, weight: .medium))
                    MultiNativePopUp(title: model.text("Save results"), selection: $model.output, options: [
                        .init(model.text("Next to the original"), "next"),
                        .init(model.text("In a MultiShift folder"), "folder"),
                        .init(copy("выбранная папка", "chosen folder"), "custom")])
                        .frame(height: 28)
                    Text(model.output == "folder"
                        ? copy("папка MultiShift создаётся рядом с каждым исходным файлом: <папка исходного файла>/MultiShift. это не единая папка на маке.", "a MultiShift subfolder is created next to each original: <original folder>/MultiShift. there is no single global folder.")
                        : model.output == "next"
                            ? copy("готовые копии сохраняются в той же папке, где находится исходный файл.", "completed copies are saved in the same folder as each original.")
                            : copy("все готовые копии сохраняются в выбранной папке.", "all completed copies are saved in the chosen folder."))
                        .font(.system(size: 11)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
                    if model.output == "custom" {
                        Text(model.customOutputPath.isEmpty ? copy("папка ещё не выбрана", "no folder selected") : model.customOutputPath)
                            .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            MultiNativeAction(title: copy("выбрать папку…", "choose folder…"), action: model.chooseOutputFolder)
                            MultiNativeAction(title: copy("открыть в finder", "open in finder"), action: model.showOutputFolder)
                                .disabled(model.customOutputPath.isEmpty)
                        }
                    }

                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(model.text("JPG / WebP quality"), systemImage: "slider.horizontal.3")
                        Spacer()
                        Text("\(model.jpgQuality)%").monospacedDigit().foregroundStyle(secondaryInk)
                    }.font(.system(size: 12))
                    Slider(value: Binding(get: { Double(model.jpgQuality) }, set: { model.jpgQuality = Int($0.rounded()) }), in: 60...100)
                        .accessibilityLabel(model.text("JPG / WebP quality"))
                }
                Divider()
                SettingsRow(model.text("PDF image resolution"), icon: "doc.richtext") {
                    Picker("", selection: $model.pdfDPI) {
                        Text("150 dpi").tag(150); Text("200 dpi").tag(200); Text("300 dpi").tag(300)
                    }.labelsHidden().frame(width: 120).accessibilityLabel(model.text("PDF image resolution"))
                }
            }
            reassurance
        }
    }
    private var appearance: some View {
        Group {
            PaneHeading(title: model.text("Appearance"), subtitle: copy("свет, графит и ничего лишнего", "light, graphite and nothing extra"), symbol: "circle.lefthalf.filled")
            SettingsGroup {
                HStack(spacing: 10) {
                    themeOption("system", title: model.text("System"), symbol: "circle.lefthalf.filled")
                    themeOption("light", title: model.text("Light"), symbol: "sun.max")
                    themeOption("dark", title: model.text("Dark"), symbol: "moon")
                }
                Divider()
                SettingsRow(model.text("Language"), icon: "character.bubble") {
                    MultiNativePopUp(title: model.text("Language"), selection: $model.language,
                        options: [.init(model.text("Russian"), "ru"), .init(model.text("English"), "en")])
                        .frame(width: 150, height: 28)
                }
            }
            Text(copy("новый язык окна обновления применяется после перезапуска приложения.", "restart the app to apply the new language to update dialogs."))
                .font(.system(size: 11)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
            Text(copy("анимации и прозрачность следуют настройкам универсального доступа macos.", "motion and transparency follow macos accessibility settings."))
                .font(.system(size: 11)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func themeOption(_ value: String, title: String, symbol: String) -> some View {
        MultiThemeChoiceView(value: value, title: title, selection: $model.appearance)
            .frame(maxWidth: .infinity).frame(height: 98)
    }
    private var notifications: some View {
        Group {
            PaneHeading(title: model.text("Notifications"), subtitle: copy("по завершении каждой фоновой операции", "after every background operation"), symbol: "bell")
            SettingsGroup {
                SettingsValueRow(title: model.text("Permission"), value: model.notificationPermission)
                Divider()
                SettingsValueRow(title: model.text("Last send"), value: model.notificationLastResult.isEmpty ? model.text("Not sent") : model.notificationLastResult)
                Divider()
                HStack(spacing: 8) {
                    MultiNativeAction(title: model.text("Test notification"), action: model.testNotification)
                    MultiNativeAction(title: model.text("Open macOS settings"), action: model.openNotificationSettings)
                }
            }
            Text(model.text("macOS may hide banners during Focus or screen sharing. Operation results remain available in MultiShift."))
                .font(.system(size: 11)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var about: some View {
        Group {
            PaneHeading(title: model.text("About"), subtitle: copy("маленькая утилита для повседневных файлов", "a small utility for everyday files"), symbol: "info.circle")
            SettingsGroup {
                HStack(spacing: 12) {
                    AppMark(size: 40)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("multishift").font(.system(size: 17, weight: .semibold)).tracking(-0.3)
                        Text("\(model.text("Version")) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                            .font(.system(size: 11)).foregroundStyle(secondaryInk)
                    }
                    Spacer()
                }.padding(.vertical, 2)
                Divider()
                MultiDisclosure(title: copy("техническая информация", "technical information")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(copy("обработка файлов выполняется локально. исходные файлы сохраняются; результаты создаются как копии.", "files are processed locally. originals are preserved and results are created as copies."))
                        Text(copy("движок: ", "engine: ") + (Bundle.main.infoDictionary?["MultiShiftEngineVersion"] as? String ?? "—"))
                        Text(copy("система: macOS ", "system: macOS ") + ProcessInfo.processInfo.operatingSystemVersionString)
                        Text(copy("архитектура: ", "architecture: ") + Self.architecture)
                        Text(copy("приложение: ", "application: ") + Bundle.main.bundleURL.path)
                        Text(copy("данные: ", "data: ") + (MultiAuditEnvironment.root?.path ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MultiShift").path))
                        Text(copy("сборка: ", "build: ") + (Bundle.main.infoDictionary?["MultiShiftBuildID"] as? String ?? "—"))
                            .font(.system(size: 10, design: .monospaced))
                        Text(copy("обновления: Sparkle · установка после подтверждения", "updates: Sparkle · installation requires confirmation"))
                    }.font(.system(size: 11)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                }.font(.system(size: 11)).foregroundStyle(secondaryInk)
            }
            SettingsGroup { UpdateSettingsView(russian: model.language == "ru") }
            reassurance
        }
    }
    private var deletionConfirmationCard: some View {
            SettingsGroup {
                Text(copy("подтверждение удаления", "deletion confirmation"))
                    .font(.system(size: 12, weight: .semibold))
                VStack(alignment: .leading, spacing: 6) {
                    MultiDeletionPreference(defaults: AppModel.defaults, russian: model.language == "ru")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(copy("для записей истории операций. без галочки запись удаляется сразу. сами файлы сохраняются.",
                              "applies to operation history. when unchecked, entries are deleted immediately. the files are preserved."))
                        .font(.system(size: 11)).foregroundStyle(secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
    }

    private var reassurance: some View {
        Label(model.text("All operations make a copy. Originals are preserved."), systemImage: "checkmark.shield")
            .font(.system(size: 11)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsGroup<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: MultiInterfaceMetrics.cardPadding) { content }
            .padding(MultiInterfaceMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .monoSurface()
            .background {
                if ProcessInfo.processInfo.environment["MULTI_ECOSYSTEM_REVIEW"] != nil {
                    MultiMeasurement(kind: "card", radius: MultiInterfaceMetrics.Radius.lg)
                }
            }
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let control: Control
    init(_ title: String, icon: String, @ViewBuilder control: () -> Control) {
        self.title = title; self.icon = icon; self.control = control()
    }
    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: icon).font(.system(size: 12))
            Spacer(minLength: 14)
            control
        }.frame(minHeight: 28)
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(secondaryInk)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.system(size: 12))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

struct WheelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var wheel: WheelPresentation
    let geometry: WheelGeometry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    private var circleInk: Color { Color(nsColor: MultiDesign.ink) }
    private var secondaryInk: Color { Color(nsColor: MultiDesign.secondary) }
    private var lineWidth: CGFloat { model.increaseContrast ? 1.5 : 1 / max(1, displayScale) }
    private var selected: ActionItem? {
        wheel.selectedIndex.flatMap { wheel.items.indices.contains($0) ? wheel.items[$0] : nil }
    }

    var body: some View {
        ZStack {
            Circle()
                // A solid neutral surface keeps small labels readable over every desktop.
                .fill(Color(nsColor: MultiDesign.card))
                .overlay(Circle().strokeBorder(circleInk.opacity(model.increaseContrast ? 0.6 : 0.16), lineWidth: lineWidth))
                .frame(width: geometry.outerRadius * 2, height: geometry.outerRadius * 2)
                .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 4)
            ForEach(Array(wheel.items.enumerated()), id: \.element.id) { index, item in
                let angle = geometry.angle(for: index, count: wheel.items.count)
                let halfStep = Double.pi / Double(max(1, wheel.items.count))
                WheelSector(start: angle - halfStep, end: angle + halfStep, geometry: geometry)
                    .fill(circleInk.opacity(wheel.selectedIndex == index ? (model.increaseContrast ? 0.22 : 0.12) : 0))
                    .animation(reduceMotion ? nil : .easeOut(duration: MultiInterfaceMetrics.hoverDuration), value: wheel.selectedIndex)
                Path { path in
                    path.move(to: geometry.point(angle: angle - halfStep, radius: geometry.cancelRadius))
                    path.addLine(to: geometry.point(angle: angle - halfStep, radius: geometry.outerRadius))
                }
                .stroke(circleInk.opacity(model.increaseContrast ? 0.5 : 0.12), lineWidth: lineWidth)
                VStack(spacing: 6) {
                    Image(systemName: item.symbol).font(.system(size: 18, weight: .medium)).frame(height: 22)
                    Text(item.shortTitle.lowercased()).font(.system(size: 11, weight: .medium))
                        .lineLimit(2).multilineTextAlignment(.center)
                }
                .foregroundStyle(wheel.selectedIndex == index ? circleInk : secondaryInk)
                .frame(width: 72, height: 52)
                .position(geometry.point(angle: angle, radius: geometry.labelRadius))
                .accessibilityLabel("\(item.title). \(item.hint)")
                .accessibilityAddTraits(wheel.selectedIndex == index ? .isSelected : [])
            }
            VStack(spacing: 6) {
                Text(wheel.mode == "tools" ? model.text("Tools") : model.text("Formats"))
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(secondaryInk)
                Image(systemName: "xmark").font(.system(size: 16, weight: .medium))
                Text(model.language == "ru" ? "отменить" : "cancel").font(.system(size: 12, weight: .medium))
                Text("esc").font(.system(size: 10)).foregroundStyle(secondaryInk)
                if let selected {
                    Text(selected.title).font(.system(size: 10, weight: .medium))
                        .lineLimit(2).multilineTextAlignment(.center).foregroundStyle(secondaryInk)
                }
            }
            .foregroundStyle(circleInk)
            .frame(width: geometry.cancelRadius * 2, height: geometry.cancelRadius * 2)
            .background(Color(nsColor: MultiDesign.canvas), in: Circle())
            .overlay(Circle().strokeBorder(circleInk.opacity(model.increaseContrast ? 0.6 : 0.16), lineWidth: lineWidth))
            .position(geometry.center)
            .accessibilityLabel(model.language == "ru" ? "отменить, escape" : "cancel, escape")
        }
        .frame(width: geometry.diameter, height: geometry.diameter)
        .scaleEffect(reduceMotion || wheel.isPresented ? 1 : 0.97)
        .opacity(wheel.isPresented ? 1 : 0)

        .onChange(of: reduceMotion) { _, reduced in
            if reduced { var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { wheel.isPresented = true }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.text("Choose an action"))
    }
}

private struct WheelSector: Shape {
    let start: Double
    let end: Double
    let geometry: WheelGeometry
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: geometry.point(angle: start, radius: geometry.cancelRadius))
        path.addLine(to: geometry.point(angle: start, radius: geometry.outerRadius))
        path.addArc(center: geometry.center, radius: geometry.outerRadius,
                    startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        path.addLine(to: geometry.point(angle: end, radius: geometry.cancelRadius))
        path.addArc(center: geometry.center, radius: geometry.cancelRadius,
                    startAngle: .radians(end), endAngle: .radians(start), clockwise: true)
        path.closeSubpath()
        return path
    }
}

struct ActionChooserView: View {
    @ObservedObject var model: AppModel
    let files: [URL]
    let close: () -> Void
    @State private var mode = "convert"
    @State private var selection = 0
    @FocusState private var chooserFocused: Bool

    private var items: [ActionItem] { model.actions(for: files, mode: mode == "convert" ? nil : "tools") }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                AppMark(size: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.text("Choose an action")).font(.system(size: 20, weight: .semibold)).tracking(-0.4)
                    Text(files.map(\.lastPathComponent).joined(separator: ", "))
                        .font(.system(size: 11)).foregroundStyle(secondaryInk).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            Picker("", selection: $mode) {
                Text(model.text("Formats")).tag("convert")
                Text(model.text("Tools")).tag("tools")
            }.pickerStyle(.segmented).accessibilityLabel(model.text("Choose an action"))
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(items) { item in
                            Button {
                                if let index = items.firstIndex(where: { $0.id == item.id }) { selection = index }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.symbol).font(.system(size: 17)).frame(width: 30)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title.lowercased()).font(.system(size: 12, weight: .medium))
                                        Text(item.hint.lowercased()).font(.system(size: 11)).foregroundStyle(secondaryInk)
                                    }
                                    Spacer()
                                    if items.indices.contains(selection) && items[selection].id == item.id {
                                        Keycap(text: "↩").accessibilityHidden(true)
                                    }
                                }.padding(.horizontal, 12).padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(ActionRowStyle(selected: items.indices.contains(selection) && items[selection].id == item.id))
                            .simultaneousGesture(TapGesture(count: 2).onEnded { model.select(item, files: files); close() })
                            .id(item.id)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(item.title). \(item.hint)")
                            .accessibilityHint(model.text("Press Return or double-click to open."))
                            .accessibilityAddTraits(items.indices.contains(selection) && items[selection].id == item.id ? .isSelected : [])
                        }
                        if items.isEmpty {
                            Text(model.text("No files were created.")).font(.system(size: 12)).foregroundStyle(secondaryInk).padding(24)
                        }
                    }.padding(6)
                }.monoSurface()
                .onChange(of: selection) {
                    guard items.indices.contains(selection) else { return }
                    withAnimation(nil) { proxy.scrollTo(items[selection].id, anchor: .center) }
                }
            }
            HStack(spacing: 5) {
                Keycap(text: "↑"); Keycap(text: "↓")
                Text(model.language == "ru" ? "выбрать" : "choose").font(.system(size: 10)).foregroundStyle(secondaryInk)
                Spacer()
                Button(model.text("Cancel"), action: close).buttonStyle(MonoButtonStyle()).keyboardShortcut(.cancelAction)
                Button(model.text("Open"), action: openSelection).buttonStyle(MonoButtonStyle(primary: true))
                    .disabled(items.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520, height: 490)
        .background(Mono.canvas).foregroundStyle(graphite).tint(graphite)

        .focusable().focusEffectDisabled().focused($chooserFocused)
        .onAppear { chooserFocused = true }
        .onKeyPress(.downArrow) { selection = min(selection + 1, max(0, items.count - 1)); return .handled }
        .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
        .onKeyPress(.return) { openSelection(); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        .onChange(of: mode) { selection = 0; chooserFocused = true }
    }

    private func openSelection() {
        guard items.indices.contains(selection) else { return }
        model.select(items[selection], files: files); close()
    }

}

struct OperationDetailsView: View {
    @ObservedObject var model: AppModel
    let operation: RecentOperation
    let showInFinder: () -> Void
    let undo: () -> Void
    let delete: () -> Void

    private var current: RecentOperation { model.operation(id: operation.id) ?? operation }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label(current.title.lowercased(), systemImage: statusSymbol)
                    .font(.system(.title2, weight: .semibold))
                    .foregroundStyle(graphite)
                Text(current.actionTitle.lowercased()).font(.system(.body, weight: .medium))
                Text(detailCopy).font(.body).foregroundStyle(secondaryInk)
                if let delivery = current.notificationDelivery {
                    Text("\(model.text("Notifications")): \(delivery.lowercased())")
                        .font(.footnote).foregroundStyle(secondaryInk)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).monoSurface()
            VStack(alignment: .leading, spacing: 10) {
                Text(model.text("Input files")).font(.headline)
                ForEach(Array(current.inputNames.enumerated()), id: \.offset) { _, name in
                    Label(name, systemImage: "doc")
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if !current.outputPaths.isEmpty {
                    Text(model.text("Output files")).font(.headline).padding(.top, 8)
                    ForEach(Array(current.outputPaths.enumerated()), id: \.offset) { _, path in
                        Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "doc.badge.arrow.up")
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                ForEach(Array((current.failures ?? []).enumerated()), id: \.offset) { _, failure in
                    VStack(alignment: .leading, spacing: 3) {
                        Text([failure.fileName, failure.stage, failure.code].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(graphite)
                            .lineLimit(2)
                        Text(failure.message).font(.system(size: 12)).foregroundStyle(secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).monoSurface()
            if current.status != .running { Spacer(minLength: 0) }
            Text(model.text("Operation history is stored on this Mac."))
                .font(.footnote).foregroundStyle(secondaryInk)
            HStack {
                Button(model.language == "ru" ? "удалить из истории" : "delete from history", action: delete)
                    .buttonStyle(MonoButtonStyle()).disabled(current.status == .running)
                if let first = current.outputPaths.first {
                    Button(model.language == "ru" ? "открыть" : "open") { model.openOutput(at: first) }
                    Button(model.text("Show outputs in Finder"), action: showInFinder)
                        .buttonStyle(MonoButtonStyle())
                }
                Spacer()
                if current.canUndo {
                    Button(model.text("Undo"), action: undo)
                        .buttonStyle(MonoButtonStyle())
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 560, height: 420)
        .background(Mono.canvas).tint(graphite)

    }

    private var detailCopy: String {
        // Engine diagnostics can contain source paths unavailable in old history
        // records. They are technical data, not owned interface copy.
        if current.status == .failed || current.status == .partial || current.status == .undoFailed {
            return current.detail
        }
        return interfaceCopy(current.detail, preserving: current.inputNames + current.outputPaths
                             + current.outputPaths.map { URL(fileURLWithPath: $0).lastPathComponent })
    }

    private var statusSymbol: String {
        switch current.status {
        case .completed: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.circle.fill"
        case .failed, .undoFailed: return "xmark.circle.fill"
        case .cancelled: return "xmark.circle"
        case .undone: return "arrow.uturn.backward.circle.fill"
        case .running: return "clock"
        }
    }
}

extension Notification.Name { static let multiSidebarToggle = Notification.Name("multi.settings.sidebar.toggle") }
