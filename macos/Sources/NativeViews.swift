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

struct EditorView: View {
    @ObservedObject var model: AppModel
    let files: [URL]
    let action: ActionItem
    let close: () -> Void

    @State private var preview: PreviewInfo?
    @State private var sourceImage: NSImage?
    @State private var metadata: [String: String] = [:]
    @State private var error: String?
    @State private var busy = false
    @State private var fitPreview = true
    @State private var selection = CGRect(x: 0.12, y: 0.12, width: 0.76, height: 0.76)
    @State private var brightness = 1.0
    @State private var contrast = 1.0
    @State private var saturation = 1.0
    @State private var warmth = 0.0
    @State private var sharpness = 1.0
    @State private var rotation = 0
    @State private var quality = 72.0
    @State private var maxSide = 0
    @State private var resizeMode = "pct"
    @State private var resizeValue = 50.0
    @State private var width = 1920.0
    @State private var height = 1080.0
    @State private var keepProportions = true
    @State private var backgroundPadding = 0.12
    @State private var backgroundRadius = 24.0
    @State private var backgroundPreset = "soft"
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var annotationKind = "rect"
    @State private var annotationText = ""
    @State private var metadataMode = "strip"
    @State private var dragAnchor: CGPoint?
    @State private var previewPan = CGSize.zero
    @State private var panAtDrag = CGSize.zero
    @State private var previewRevision = 0
    @State private var compareOriginal = false

    private var toolName: String { action.id.replacingOccurrences(of: "tool:", with: "") }
    private var path: String { files.first?.path ?? "" }
    private var sourceWidth: Int { preview?.sourceWidth ?? preview?.width ?? 1 }
    private var sourceHeight: Int { preview?.sourceHeight ?? preview?.height ?? 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: action.symbol).font(.system(size: 18)).frame(width: 36, height: 36).monoSurface(radius: MultiInterfaceMetrics.Radius.sm)
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title.lowercased()).font(.system(size: 17, weight: .semibold))
            Text(files.first?.lastPathComponent ?? "").font(.system(size: 12)).foregroundStyle(secondaryInk).lineLimit(1)
                }
                Spacer()
                if files.count > 1 {
                    Text("\(files.count) \(model.language == "ru" ? "файла" : "files")")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(secondaryInk)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 13)
            Divider()
            GeometryReader { geometry in
                let narrow = geometry.size.width < 840
                let layout = narrow ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
                layout {
                    previewPane.frame(minHeight: 160)
                    Divider()
                    inspector.frame(width: narrow ? nil : 272)
                        .frame(maxHeight: narrow ? 220 : .infinity)
                }
            }
            Divider()
            HStack {
                Text(model.text("All operations make a copy. Originals are preserved."))
                    .font(.system(size: 12)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button(model.text("Cancel"), action: close).buttonStyle(MonoButtonStyle()).keyboardShortcut(.cancelAction)
                Button(model.text("Save Copy"), action: save)
                    .buttonStyle(MonoButtonStyle(primary: true))
                    .disabled(!canSave || busy)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(Mono.canvas)

        .tint(graphite)
        .onAppear {
            if toolName == "Redact" || toolName == "Annotate" { selection = .zero }
            loadPreview()
        }
        .onChange(of: width) { _, value in
            guard resizeMode == "exact", keepProportions, sourceWidth > 0 else { return }
            height = value * Double(sourceHeight) / Double(sourceWidth)
        }
        .onChange(of: height) { _, value in
            guard resizeMode == "exact", keepProportions, sourceHeight > 0 else { return }
            width = value * Double(sourceWidth) / Double(sourceHeight)
        }
        .onChange(of: fitPreview) { previewPan = .zero; loadPreview() }
    }

    private var canSave: Bool {
        if toolName == "Protect" { return password.count >= 4 && password == passwordConfirm }
        if toolName == "Redact" { return selection.width > 0.03 && selection.height > 0.03 }
        if toolName == "Annotate" { return !annotationText.isEmpty || selection.width > 0.03 }
        return true
    }

    private var previewPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label(model.text("Preview"), systemImage: "viewfinder").font(.system(size: 12, weight: .medium))
                Spacer()
                if sourceWidth > 1 {
                    Text("\(sourceWidth) × \(sourceHeight)").font(.system(size: 11, design: .monospaced)).foregroundStyle(secondaryInk)
                }
                if toolName == "Edit" {
                    Text(model.text("Before"))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(secondaryInk)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: MultiInterfaceMetrics.Radius.sm))
                        .onLongPressGesture(minimumDuration: 0, pressing: { compareOriginal = $0 }, perform: {})
                        .accessibilityLabel(model.language == "ru" ? "удерживайте, чтобы сравнить с оригиналом" : "hold to compare with original")
                }
                Picker("", selection: $fitPreview) {
                    Text(model.text("Fit")).tag(true)
                    Text("100%").tag(false)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 116)
            }.padding(.horizontal, 14).padding(.vertical, 9)
            Divider()
            GeometryReader { geometry in
                let image = sourceImage
                ZStack {
                    Checkerboard()
                    if let image {
                        let size = image.size
                        let fitScale = min((geometry.size.width - 32) / max(size.width, 1), (geometry.size.height - 32) / max(size.height, 1))
                        let displayScale = fitPreview ? fitScale : 1
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: size.width * displayScale, height: size.height * displayScale)
                            .saturation(toolName == "Edit" && !compareOriginal ? saturation : 1)
                            .contrast(toolName == "Edit" && !compareOriginal ? contrast : 1)
                            .brightness(toolName == "Edit" && !compareOriginal ? brightness - 1 : 0)
                            .rotationEffect(.degrees(toolName == "Edit" && !compareOriginal ? Double(rotation) : 0))
                            .overlay(selectionOverlay(size: geometry.size))
                            .offset(fitPreview ? .zero : previewPan)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    } else if let error {
                        VStack(spacing: 9) {
                            Image(systemName: "doc").font(.system(size: 28)).foregroundStyle(secondaryInk)
                            Text(interfaceCopy(error, preserving: files.flatMap { [$0.path, $0.lastPathComponent] })).font(.system(size: 12)).foregroundStyle(secondaryInk).multilineTextAlignment(.center)
                        }.padding(30)
                    } else {
                        ProgressView().controlSize(.regular)
                    }
                    if busy {
                        ProgressView(model.text("Working…"))
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(model.reduceTransparency
                                ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                                : AnyShapeStyle(.regularMaterial), in: RoundedRectangle(cornerRadius: MultiInterfaceMetrics.Radius.lg))
                    }
                }
                .gesture(canvasGesture(geometry.size))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            if toolName == "Crop" || toolName == "Redact" || toolName == "Annotate" {
                HStack {
                    Label(model.text("Select region"), systemImage: "selection.pin.in.out")
                    Spacer()
                    Text("\(Int(selection.width * Double(sourceWidth))) × \(Int(selection.height * Double(sourceHeight))) px")
                        .font(.system(size: 11, design: .monospaced))
                }
                .font(.system(size: 11)).foregroundStyle(secondaryInk)
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.text(toolName)).font(.system(size: 17, weight: .semibold))
                switch toolName {
                case "Crop":
                    Text(model.text("Use the drag area to select a region.")).font(.system(size: 12)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
                    InspectorValue(model.text("Width"), value: "\(Int(selection.width * Double(sourceWidth))) px")
                    InspectorValue(model.text("Height"), value: "\(Int(selection.height * Double(sourceHeight))) px")
                    Button(model.language == "ru" ? "сбросить выделение" : "reset selection") { selection = CGRect(x: 0, y: 0, width: 1, height: 1) }
                        .buttonStyle(MonoButtonStyle())
                case "Redact":
                    Text(model.text("Use the drag area to select a region.")).font(.system(size: 12)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
                    Label(model.text("Black redaction"), systemImage: "eye.slash.fill").font(.system(size: 12, weight: .medium))
                    Text(model.language == "ru" ? "скрытие записывается в новую копию." : "redaction is burned into a new copy.")
                        .font(.system(size: 11)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
                case "Annotate":
                    Picker(model.language == "ru" ? "фигура" : "mark", selection: $annotationKind) {
                        Text(model.language == "ru" ? "прямоугольник" : "rectangle").tag("rect")
                        Text(model.language == "ru" ? "стрелка" : "arrow").tag("arrow")
                        Text(model.language == "ru" ? "овал" : "ellipse").tag("ellipse")
                        Text(model.language == "ru" ? "подпись" : "text").tag("text")
                    }
                    if annotationKind == "text" {
                        TextField(model.text("Annotation text"), text: $annotationText)
                            .textFieldStyle(MonoTextFieldStyle())
                    }
                    Text(model.text("Use the drag area to select a region.")).font(.system(size: 12)).foregroundStyle(secondaryInk)
                case "Edit":
                    sliderRow("Brightness", value: $brightness, range: 0.5...1.5, display: "\(Int((brightness - 1) * 100))%")
                    sliderRow("Contrast", value: $contrast, range: 0.5...1.5, display: "\(Int((contrast - 1) * 100))%")
                    sliderRow("Saturation", value: $saturation, range: 0...2, display: "\(Int(saturation * 100))%")
                    sliderRow("Warmth", value: $warmth, range: -1...1, display: "\(Int(warmth * 100))")
                    sliderRow("Sharpness", value: $sharpness, range: 0...2, display: "\(Int(sharpness * 100))%")
                    Picker(model.text("Rotate"), selection: $rotation) {
                        Text("0°").tag(0); Text("90°").tag(90); Text("180°").tag(180); Text("270°").tag(270)
                    }
                    Button(model.language == "ru" ? "сбросить коррекцию" : "reset adjustments") {
                        brightness = 1; contrast = 1; saturation = 1; warmth = 0; sharpness = 1; rotation = 0
                    }.buttonStyle(MonoButtonStyle())
                case "Add BG":
                    Picker(model.text("Format"), selection: $backgroundPreset) {
                        Text(model.language == "ru" ? "мягкий светлый" : "soft light").tag("soft")
                        Text(model.language == "ru" ? "графит" : "graphite").tag("graphite")
                    }
                    sliderRow("Background padding", value: $backgroundPadding, range: 0...0.4, display: "\(Int(backgroundPadding * 100))%")
                    sliderRow("Corner radius", value: $backgroundRadius, range: 0...100, display: "\(Int(backgroundRadius)) px")
                case "Compress":
                    sliderRow("Quality", value: $quality, range: 10...95, display: "\(Int(quality))%")
                    Picker(model.text("Maximum side"), selection: $maxSide) {
                        Text(model.language == "ru" ? "исходный размер" : "original size").tag(0)
                        Text("3840 px").tag(3840); Text("2560 px").tag(2560); Text("1920 px").tag(1920)
                        Text("1280 px").tag(1280); Text("800 px").tag(800)
                    }
                case "Resize":
                    Picker(model.language == "ru" ? "размер" : "size", selection: $resizeMode) {
                        Text(model.language == "ru" ? "процент" : "percent").tag("pct")
                        Text(model.language == "ru" ? "длинная сторона" : "longest side").tag("long")
                        Text(model.language == "ru" ? "точный размер" : "exact size").tag("exact")
                    }
                    if resizeMode == "exact" {
                        numericRow("Width", value: $width)
                        numericRow("Height", value: $height)
                        Toggle(model.text("Keep proportions"), isOn: $keepProportions).font(.system(size: 12))
                    } else {
                        sliderRow(resizeMode == "pct" ? (model.language == "ru" ? "процент" : "percent") : model.text("Maximum side"),
                                  value: $resizeValue, range: resizeMode == "pct" ? 10...200 : 100...6000,
                                  display: resizeMode == "pct" ? "\(Int(resizeValue))%" : "\(Int(resizeValue)) px")
                    }
                case "Metadata":
                    if metadata.isEmpty {
                        ProgressView().controlSize(.small)
                    } else {
                        ForEach(metadata.keys.sorted().prefix(12), id: \.self) { key in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(key).font(.system(size: 10, weight: .medium)).foregroundStyle(secondaryInk)
                                Text(metadata[key] ?? "").font(.system(size: 12)).lineLimit(2).textSelection(.enabled)
                            }
                            Divider()
                        }
                    }
                    Picker(model.language == "ru" ? "удалить" : "remove", selection: $metadataMode) {
                        Text(model.text("Remove all metadata")).tag("strip")
                        if metadata.keys.contains(where: { $0.localizedCaseInsensitiveContains("gps") || $0.localizedCaseInsensitiveContains("location") }) {
                            Text(model.text("Remove location only")).tag("location")
                        }
                    }
                case "Protect":
                    SecureField(model.text("Password"), text: $password).textFieldStyle(MonoTextFieldStyle())
                    SecureField(model.text("Confirm password"), text: $passwordConfirm).textFieldStyle(MonoTextFieldStyle())
                    Text(model.language == "ru" ? "pdf будет зашифрован aes-256." : "the pdf will use aes-256 encryption.")
                        .font(.system(size: 11)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
                    if !passwordConfirm.isEmpty && password != passwordConfirm {
                        Text(model.language == "ru" ? "пароли не совпадают." : "passwords do not match.")
                            .font(.system(size: 11)).foregroundStyle(graphite)
                    }
                default:
                    Text(action.hint.lowercased()).font(.system(size: 12)).foregroundStyle(secondaryInk)
                }
            }
            .padding(18)
            .monoSurface()
            .padding(12)
        }
        .background(Mono.canvas)
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(model.text(title)).font(.system(size: 12)); Spacer(); Text(display).font(.system(size: 11, design: .monospaced)).foregroundStyle(secondaryInk) }
            Slider(value: value, in: range).tint(graphite)
        }.padding(.vertical, 3)
    }

    private func numericRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(model.text(title)).font(.system(size: 12))
            Spacer()
            TextField("", value: value, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(MonoTextFieldStyle()).frame(width: 82)
            Text("px").font(.system(size: 11)).foregroundStyle(secondaryInk)
        }
    }

    @ViewBuilder private func selectionOverlay(size: CGSize) -> some View {
        if toolName == "Crop" || toolName == "Redact" || toolName == "Annotate" {
            GeometryReader { geometry in
                let display = fittedRect(image: sourceImage?.size ?? .zero, in: geometry.size)
                let rect = CGRect(x: display.minX + selection.minX * display.width,
                                  y: display.minY + selection.minY * display.height,
                                  width: selection.width * display.width,
                                  height: selection.height * display.height)
                ZStack(alignment: .topLeading) {
                    if toolName == "Crop" {
                        Path { path in
                            path.addRect(CGRect(origin: .zero, size: geometry.size))
                            path.addRect(rect)
                        }.fill(Color.black.opacity(0.42), style: FillStyle(eoFill: true))
                    }
                    if toolName == "Redact" { Rectangle().fill(.black).frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY) }
                    if toolName == "Annotate" && annotationKind == "rect" {
                        Rectangle().stroke(graphite, lineWidth: 2).frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
                    } else if toolName == "Annotate" && annotationKind == "text" && !annotationText.isEmpty {
                        Text(annotationText).font(.system(size: 13, weight: .medium)).foregroundStyle(graphite)
                            .position(x: rect.minX + rect.width / 2, y: rect.minY + rect.height / 2)
                    }
                    if toolName == "Crop" {
                        Rectangle().stroke(.white.opacity(0.92), lineWidth: 1.2)
                            .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .allowsHitTesting(false)
        }
    }

    private func canvasGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let isSelecting = toolName == "Crop" || toolName == "Redact" || toolName == "Annotate"
                if isSelecting {
                    let imageSize = sourceImage?.size ?? .zero
                    let rect = fitPreview ? fittedRect(image: imageSize, in: size) :
                        CGRect(x: size.width / 2 - imageSize.width / 2 + previewPan.width,
                               y: size.height / 2 - imageSize.height / 2 + previewPan.height,
                               width: imageSize.width, height: imageSize.height)
                    let start = dragAnchor ?? normalizedPoint(value.startLocation, in: rect)
                    if dragAnchor == nil { dragAnchor = start }
                    let end = normalizedPoint(value.location, in: rect)
                    let x = min(start.x, end.x), y = min(start.y, end.y)
                    selection = CGRect(x: x, y: y, width: max(0.025, abs(end.x - start.x)), height: max(0.025, abs(end.y - start.y)))
                } else if !fitPreview {
                    previewPan = CGSize(width: panAtDrag.width + value.translation.width,
                                        height: panAtDrag.height + value.translation.height)
                }
            }
            .onEnded { value in
                if toolName == "Crop" || toolName == "Redact" || toolName == "Annotate" {
                    dragAnchor = nil
                } else if !fitPreview {
                    panAtDrag = CGSize(width: panAtDrag.width + value.translation.width,
                                       height: panAtDrag.height + value.translation.height)
                }
            }
    }

    private func fittedRect(image: CGSize, in frame: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return CGRect(origin: .zero, size: frame) }
        let ratio = min(frame.width / image.width, frame.height / image.height)
        let size = CGSize(width: image.width * ratio, height: image.height * ratio)
        return CGRect(x: (frame.width - size.width) / 2, y: (frame.height - size.height) / 2, width: size.width, height: size.height)
    }

    private func normalizedPoint(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: min(1, max(0, (point.x - rect.minX) / max(rect.width, 1))),
                y: min(1, max(0, (point.y - rect.minY) / max(rect.height, 1))))
    }

    private func loadPreview() {
        previewRevision += 1
        let revision = previewRevision
        guard let sourceURL = files.first else { error = model.text("Couldn't load preview"); return }
        model.preview(url: sourceURL, maxSide: fitPreview ? 1800 : 4096) { info, fields, error in
            guard revision == previewRevision else {
                if let info { try? FileManager.default.removeItem(at: info.url) }
                return
            }
            self.preview = info
            self.metadata = fields
            self.error = error
            if let info {
                if let data = try? Data(contentsOf: info.url) { self.sourceImage = NSImage(data: data) }
                try? FileManager.default.removeItem(at: info.url)
            }
        }
    }

    private func save() {
        busy = true
        var parameters: [String: Any] = [:]
        let x = max(0, min(sourceWidth - 1, Int(Double(selection.minX) * Double(sourceWidth))))
        let y = max(0, min(sourceHeight - 1, Int(Double(selection.minY) * Double(sourceHeight))))
        let w = max(1, min(sourceWidth - x, Int(Double(selection.width) * Double(sourceWidth))))
        let h = max(1, min(sourceHeight - y, Int(Double(selection.height) * Double(sourceHeight))))
        switch toolName {
        case "Crop": parameters = ["x": x, "y": y, "width": w, "height": h]
        case "Redact": parameters = ["rects": [[x, y, x + w, y + h]], "mode": "black"]
        case "Annotate":
            parameters = ["items": [["kind": annotationKind, "box": [x, y, x + w, y + h], "text": annotationText, "color": "#222222", "width": 5]]]
        case "Edit":
            parameters = ["brightness": brightness, "contrast": contrast, "saturation": saturation,
                          "warmth": warmth, "sharpness": sharpness, "rotate": rotation]
        case "Add BG":
            let colors = backgroundPreset == "graphite" ? ["#55565A", "#252629"] : ["#E9E9EB", "#BFC0C4"]
            parameters = ["colors": colors, "padding": backgroundPadding,
                          "radius": Int(backgroundRadius), "shadow": 0.35, "aspect": "Auto"]
        case "Compress": parameters = ["quality": Int(quality), "max_side": maxSide]
        case "Resize":
            if resizeMode == "exact" {
                parameters = ["mode": "exact", "width": Int(width), "height": Int(height),
                              "keep_proportions": keepProportions]
            } else { parameters = ["mode": resizeMode, "value": Int(resizeValue)] }
        case "Metadata": parameters = ["mode": metadataMode]
        case "Protect": parameters = ["password": password]
        default: break
        }
        model.perform(action: action.id, files: files, parameters: parameters) { _ in
            busy = false
            close()
        }
    }
}

private struct InspectorValue: View {
    let title: String
    let value: String
    init(_ title: String, value: String) { self.title = title; self.value = value }
    var body: some View {
        HStack { Text(title).font(.system(size: 12)).foregroundStyle(secondaryInk); Spacer(); Text(value).font(.system(size: 11, design: .monospaced)).foregroundStyle(graphite) }
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 12
            for row in 0...Int(size.height / tile) {
                for column in 0...Int(size.width / tile) where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile)
                    context.fill(Path(rect), with: .color(Color(nsColor: .controlBackgroundColor).opacity(0.55)))
                }
            }
        }
        .background(Mono.canvas)
        .accessibilityHidden(true)
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
                if !current.outputPaths.isEmpty {
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
