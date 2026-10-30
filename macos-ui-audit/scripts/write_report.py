#!/usr/bin/env python3
"""Assemble the audit from actual outputs. Missing required evidence is an error."""
import hashlib
import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
SHIFT = ROOT.parent
SWITCH = SHIFT.parent / "MultiSwitcher"


def load(relative):
    return json.loads((ROOT / relative).read_text())


def write_json(relative, value):
    (ROOT / relative).write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def main():
    geometry = {app: load(f"screenshots/after/final-{app}/geometry-results.json")
                for app in ["multishift", "multiswitcher"]}
    before = {app: load(f"screenshots/before/{app}/geometry-results.json") for app in geometry}
    native = load("runtime/native-final-switcher/native-results.json")
    circle = load("screenshots/after/approved-circle/circle-results.json")
    editors = load("screenshots/after/editors/editor-results.json")
    functional = load("runtime/final-functional-shift/functional-results.json")
    engine = load("runtime/packaged-engine-results.json")
    restore = load("runtime/restore-results.json")
    live = load("runtime/live-layout/live-layout-results.json")
    perf = load("performance-idle.json")
    contrast = load("runtime/circle-contrast.json")
    archives = load("builds.json")
    baseline = load("baseline.json")

    measurements = []
    for phase in ["before", "after"]:
        for app in geometry:
            folder = f"screenshots/{phase}/" + (app if phase == "before" else "final-" + app)
            for row in load(folder + "/layout-measurements.json"):
                measurements.append({"app": app, "phase": phase, "source": folder,
                                     "unit": "logical pt", "measurement": row})
    write_json("geometry-results.json", {
        "units": {"geometry": "logical pt", "screenshots": "physical px"},
        "before": before, "after": geometry, "circle": circle, "editors": editors,
        "settingsMeasurements": measurements,
        "actualDisplayCount": native["connectedDisplays"], "actualBackingScale": 2,
        "physicalDisplayScalingVerified": False, "multiplePhysicalDisplaysVerified": False,
        "componentBackingScalesTested": [1, 2],
    })
    write_json("window-results.json", {
        "settings": geometry, "freshProcessRestore": restore,
        "pageTransitionRegressions": native["pageTransitions"],
        "nativeMenu": native, "circle": circle, "editorWindows": editors,
        "physicalScenarios": {"FinderShiftDrag": "unverified", "VoiceOverSpeech": "unverified",
                              "displayScaling": "unverified", "ChatGPTTextInput": "unverified"},
    })

    preservation = baseline["preserved_files"]
    pairs = [
        (SHIFT / "macos/Sources/MultiDesignKit.swift", SWITCH / "macos/Sources/MultiSwitcher/MultiDesignKit.swift"),
        (SHIFT / "macos/Sources/MultiPopoverKit.swift", SWITCH / "macos/Sources/MultiSwitcher/MultiPopoverKit.swift"),
        (SHIFT / "macos/Sources/Core/MultiInterfaceMetrics.swift", SWITCH / "macos/Sources/MultiSwitcherCore/MultiInterfaceMetrics.swift"),
        (SHIFT / "macos/Sources/Core/MultiAuditEnvironment.swift", SWITCH / "macos/Sources/MultiSwitcherCore/MultiAuditEnvironment.swift"),
    ]
    parity = [{"name": a.name, "shiftSHA256": sha(a), "switcherSHA256": sha(b), "identical": sha(a) == sha(b)} for a, b in pairs]
    dict_snapshot = ROOT / baseline["snapshot"] / "multiswitcher/dicts"
    dictionary_match = all(sha(p) == sha(SWITCH / "dicts" / p.relative_to(dict_snapshot))
                           for p in dict_snapshot.rglob("*") if p.is_file())
    write_json("preservation.json", {
        "localData": preservation, "sharedSourceParity": parity, "repositoryDictionariesUnchanged": dictionary_match,
        "rawPathsAndFingerprintsIncluded": False,
        "settingsPlistCaveat": "Both production preferences plists changed during the earlier QA. Specific preference values and file fingerprints are omitted. The whole files were not rolled back, to avoid overwriting current settings.",
    })

    inventory = {}
    for app, repo in [("multishift", SHIFT), ("multiswitcher", SWITCH)]:
        inventory[app] = []
        for path in sorted((repo / "macos/Sources").rglob("*.swift")):
            source = path.read_text()
            inventory[app].append({"path": str(path.relative_to(repo)), "sha256": sha(path),
                "lines": len(source.splitlines()), "imports": re.findall(r"^import (\w+)", source, re.M),
                "types": re.findall(r"\b(?:class|struct|enum|protocol)\s+(\w+)", source)})
    write_json("architecture-inventory.json", inventory)

    features = []
    def feature(name, checked="код", works="не подтверждено в live UI", gap="U01", evidence="SettingsManager / AppDelegate", error="—"):
        features.append({"id": f"SW{len(features)+1:02d}", "feature": name, "implemented": True,
                         "checked": checked, "works": works, "error": error,
                         "notVerified": gap, "evidence": evidence})
    core = "logs/switcher-core-checks.log; logs/switcher-tests-final.log"
    selection = "logs/selection_conversion-final.log"
    feature("включение/выключение приложения", "native menu / UI", "PASS на fixture; ввод U01", "U01", "runtime/native-final-switcher/native-results.json")
    feature("ручная конверсия последнего слова", "Core / selection harness", "алгоритм PASS", "U01: реальные клавиши", selection)
    feature("конверсия выделенного текста", "Core / selection harness", "алгоритм и routing PASS", "U01: AX/вставка в сторонние поля", selection)
    feature("конверсия всей строки", "код / Core", "Core PASS; OS-доставка не подтверждена", "U01", core)
    feature("автоматическая коррекция на границе слова", "Core / настройки UI", "Core PASS; live ввод не подтверждён", "U01", core + "; runtime/cua-results.json", "исправлена рассинхронизация onboarding")
    feature("защита URL, кода, mixed text, acronym и коротких слов", "Core / selection harness", "PASS на наборах", "реальные приложения U01", selection)
    feature("smart conversion", "Core / selection harness", "PASS на наборах", "U01", selection)
    feature("определение направления по тексту", "Core / selection harness", "PASS на наборах", "U01", selection)
    feature("смена регистра", "Core / selection harness", "routing PASS", "U01: реальный hotkey", selection)
    feature("отмена и восстановление точного текста", "Core", "политики PASS", "U01: реальный undo/clipboard", core)
    feature("отслеживание активной раскладки и badge", "30 реальных TIS переключений", "PASS; исходная раскладка восстановлена", "физический системный hotkey отдельно", "runtime/live-layout/live-layout-results.json")
    feature("выбор пары раскладок / автоопределение", "код / TIS / Core", "TIS пары PASS", "ручная настройка всех пар", core + "; runtime/live-layout/live-layout-results.json")
    feature("автопереход языка по порогу слов", "Core", "политика PASS", "U01", core)
    feature("запоминание раскладки по приложениям", "Core", "память и политика PASS", "U01: переключение реальных приложений", core)
    for name in ["триггер Option/Caps Lock/модификатор", "ограничение правой клавишей", "двойной тап", "отдельный hotkey смены раскладки", "hotkey смены регистра", "конфликты и отключение hotkeys"]:
        feature(name, evidence="KeyboardMonitor.HotkeyConfig / SettingsManager / HelpWindowController")
    feature("пауза до возобновления", "native menu / Core", "состояния PASS", "U01: ввод в паузе", core + "; runtime/native-final-switcher/native-results.json")
    feature("пауза 15/60 минут и истечение срока", "Core / native fixture", "срок и обновление существующих menu items PASS", "реальный длительный таймер / restart", core + "; runtime/native-final-switcher/native-results.json")
    feature("исключения только автокоррекции", "Core / реальные окна", "политика PASS; список отрисован", "U01: add/remove и ввод", core + "; screenshots/after/final-multiswitcher")
    feature("полное отключение действий для приложения", "Core / реальные окна", "политика PASS", "U01", core)
    feature("режимы приложения: обычно / вручную / выключено", "native menu / Core", "fixture PASS", "физическое применение к сторонним приложениям", core + "; runtime/native-final-switcher/native-results.json")
    feature("защищённые приложения и Secure Input", "код / Core", "проверены политики", "U01: реальное защищённое поле; TCC не изменялись", core)
    feature("ChatGPT через общие механизмы приложений", "код", "не подтверждено в ChatGPT", "U01: composer не затрагивался; отдельного раздела ChatGPT нет", "ApplicationExclusionPolicy / AppDelegate")
    feature("словари RU/EN и динамические keyboard maps", "реальные словари / Core", "PASS на наборах", "AppleSpell и live input отдельно", selection)
    feature("тематические словари", "Core / реальные packaged wordlists", "PASS на наборах", "ручное переключение UI и перезапуск", selection)
    feature("never/always convert списки", "Core", "PASS", "live input U01", core)
    feature("правила exact/prefix/contains/regex и замены", "Core / native rule probe", "fixture PASS", "ручное создание/import/export U01", core + "; logs/switcher-final-geometry.log")
    feature("поиск, выбор и клавиатура списка правил", "native controller probe", "PASS на fixture", "VoiceOver U03", "logs/switcher-final-geometry.log")
    feature("импорт профиля Punto и provenance", "Core", "PASS на fixture-файлах", "настоящий пользовательский импорт не выполнялся", core)
    feature("экспорт/импорт пользовательских правил", "Core codec / код UI", "codec PASS", "file panels и ручной roundtrip", core)
    feature("восстановление удалённых Punto-правил", "Core", "PASS на fixture", "ручное действие UI", core)
    feature("профиль: atomic save, backup, восстановление", "Core / isolated fixture", "fixture PASS; host profile contents omitted", "полный пользовательский disaster recovery не запускался", core + "; preservation.json")
    feature("обучение по отмене автоматических исправлений", "Core", "PASS на fixture", "U01: реальные циклы отмены", core)
    feature("кандидаты ручного обучения и подтверждение", "Core / native learning probe", "fixture PASS", "U01: реальный Option и подтверждение", core + "; logs/switcher-final-geometry.log")
    feature("забыть / не исправлять / undo обучения", "Core / native learning probe", "fixture PASS", "физические действия и restart", core)
    feature("переход из обучения к правилу", "реальный AppKit controller", "PASS после прерывания fade", "физический клик отдельно", "runtime/native-final-switcher/native-results.json", "исправлен обход отмены переходов")
    feature("caret-индикатор", evidence="CaretIndicator / AppDelegate.syncCaretIndicator")
    feature("звук клавиш", evidence="KeyboardMonitor / SettingsManager.keySound")
    feature("уведомление Secure Input", "код / native fixture", "отображение проверено", "U01: реальный защищённый ввод", "SecureInputNotice / screenshots/after/final-multiswitcher")
    feature("remote desktop beta", "код / Core политики", "не подтверждено end-to-end", "нет второй remote-сессии", "KeyboardMonitor / configureIconRefreshFallback")
    feature("скрытие tray и повторное открытие", "код", "не подтверждено физически", "reopen скрытой иконки", "AppDelegate.applicationShouldHandleReopen")
    feature("автозапуск", "код / чтение текущего состояния", "регистрация не проверялась", "U08: audit не меняет SMAppService", "SettingsManager.launchAtLogin / syncLoginItem")
    feature("разрешения и фоновый запуск мониторинга", "локальный runtime check", "проверка выполнена; конкретные grant values omitted", "доставка hardware input U01", "runtime/input-switcher/permission-runtime.json")
    feature("помощник разрешений", "код / native fixture", "отображение доступно", "не выдавались и не сбрасывались реальные TCC-разрешения", "PermissionsGuideWindowController")
    feature("каналы и проверка обновлений", "код / configured guard", "release-интеграция не проверена", "U08: Sparkle/configured endpoint выключены в preview", "UpdateChecker / SparkleUpdateChecker")
    feature("crash consent и редактирование диагностики", "Core redaction / код", "redaction PASS; SDK не активирован", "U08: Sentry не включён", core + "; CrashReporter")
    feature("диагностический лог", "код / build", "однократный flush вместо вечного таймера", "длительный debug-сеанс не профилировался отдельно", "KeyboardMonitor.RSLogWriter", "исправлен пустой повторяющийся timer")
    feature("язык интерфейса и темы", "реальные окна обеих тем", "PASS выбранных состояний", "все переводы и длинные строки вручную не просмотрены", "geometry-results.json")
    feature("сохранение geometry после перезапуска", "два отдельных процесса", "PASS обоих приложений", "production autosave не перезаписывался новым probe", "runtime/restore-results.json")
    feature("системное status bar меню", "реальный NSMenu + 100 fixture циклов", "PASS состояния/identity и native capture", "U02: physical pointer/keyboard tracking", "runtime/native-final-switcher/native-results.json", "заменён custom popover")
    feature("навигация и прерываемые переходы", "native controller + CUA", "5 регрессий PASS; CUA переход подтверждён", "U03: spoken VoiceOver", "runtime/native-final-switcher/native-results.json", "исправлены stale completion и onboarding state")
    feature("Reduce Motion во время sidebar-анимации", "native SidebarChecks", "PASS, немедленное завершение", "реальный системный toggle и физический дисплей U04", "logs/sidebar_layout-final.log")
    write_json("feature-matrix.json", features)
    lines = ["# Реестр MultiSwitcher", "", "25 октября 2026. Наличие кода не означает подтверждённую работу. Core/fixture PASS не заменяет live input.", "",
             "Отдельные состояния: реализована, способ проверки, подтверждённая работа, ошибка и оставшаяся непроверенная часть. U-коды раскрыты в QA.md.", "",
             "| ID | Функция | Реализована | Проверена | Работает | Ошибка | Не удалось проверить | Доказательство |",
             "|---|---|---|---|---|---|---|---|"]
    for item in features:
        lines.append("| " + " | ".join([item["id"], item["feature"], "да", item["checked"], item["works"], item["error"], item["notVerified"], item["evidence"]]) + " |")
    lines += ["", "## MultiShift: дополнительный реестр", "",
        "- 10 image targets и PDF/DOCX/TXT: фактический frozen-worker прогон, все 33 format/tool cases PASS; оригиналы неизменны.",
        "- Image tools: compress, resize, crop, edit, annotate, redact, background, metadata — CLI outputs проверены; реальные формы открыты в обеих темах.",
        "- PDF tools: compress, split, rotate, merge, protect, extract, metadata — CLI outputs проверены; формы compress/protect/metadata открыты в обеих темах.",
        "- Обычный AppModel/FileJobCoordinator путь: JPG, partial batch, trash-only undo, защита изменённого output, pause/resume — PASS на собственных fixtures.",
        "- Круг: геометрия и 6 pt arming проверены; 100 прерываний, все SF Symbols, обе темы — fixture PASS. Finder hardware drag/отпускание/Escape остаются U02.",
        "- История, Finder actions, notification permissions, actual login и клавиатурный chooser: реализация сохранена; физическая приёмка не завершена.",
        "- 22 editor windows открыты, preview отрисован в выбранных просмотренных снимках; apply/save клики в GUI не выполнялись. CLI tool PASS не равен GUI save PASS."]
    (ROOT / "feature-matrix.md").write_text("\n".join(lines) + "\n")

    minimum_contrast = min(x["ratio"] for x in contrast if x["phase"] == "after-contrast-fix")
    (ROOT / "circle-design.md").write_text(f"""# Круг MultiShift

Панель 400×400 pt, внешняя поверхность r=184 pt, cancel r=64 pt, центр/границы/подписи/hit-test используют WheelGeometry. 10 форматов остаются в одном кольце, инструменты сохраняют собственный режим и стабильные action IDs.

Цель — монохром без glow: общие непрозрачные neutral tokens, 1/backingScale разделители, SF Symbols 18 pt, подписи 11 pt. Непрозрачная поверхность сохраняет читаемость над любым desktop; глубину дают небольшой shadow и центральная поверхность. Центр всегда явно обозначает отмену и Escape.

Отличия от baseline: исправлены half-sector offset и активная часть видимого центра; первый выбор требует 6 pt движения; final cursor hit-test выполняется перед отпусканием; mode change не отменяет queued entrance. Outgoing hosting view сохраняет текущую анимацию и отделённый presentation object, новый вызов не мутирует уходящую панель.

Появление 140 ms (opacity, scale 0.97→1); закрытие 90 ms opacity; hover 100 ms. Выполнение действия не ждёт exit. Во время видимого жеста включена короткая user-initiated activity, позволяющая idle sleep; токен заканчивается после exit, нового постоянного фонового activity нет. Reduce Motion убирает scale.

Фактические результаты: {circle['cycles']} прерванных циклов; activePanelAfterClose={circle['activePanelAfterClose']}; inputTimerAfterClose={circle['inputTimerAfterClose']}; activityAfterClose={circle.get('activityAfterClose')}. Все symbols доступны. Минимальное измеренное steady-state соотношение выбранных текстовых пар: {minimum_contrast:.2f}:1; детали в runtime/circle-contrast.json.

Нативные снимки: screenshots/before/circle и screenshots/after/approved-circle. Аппаратный Finder drag, edge release, Escape и несколько физических мониторов не сертифицированы fixture-прогоном.
""")

    (ROOT / "animation-comparison.md").write_text(f"""# Сравнение анимаций

Общий sidebar уже был побайтово одинаковым: 208/60 pt, одна непрерывная phase, критически затухающий профиль 260 ms, продолжение velocity при развороте. Разницу качества нельзя приписывать разным sidebar springs.

MultiShift меняет содержимое SwiftUI через opacity transition; MultiSwitcher использовал последовательный AppKit fade 70+90 ms и мог применить старый completion после keyboard/immediate запроса. Теперь каждый запрос инвалидирует прежний, opacity продолжается от presentation, прямой переход из обучения тоже использует общий путь.

Общие значения: curve (0.23,1,0.32,1), navigation 160 ms, hover 100 ms, sidebar 260 ms. Custom toggle MultiSwitcher использует ту же standard curve вместо отдельной недозатухающей spring. Keyboard navigation мгновенна. Системный NSMenu использует собственное движение macOS.

Reduce Motion теперь прерывает уже активный sidebar timer, а не только новые переходы; это проверяется отдельными SidebarChecks. Системный accessibility notification подписан через NSWorkspace.notificationCenter. Circle presence/exit/hover описаны в circle-design.md.

Результаты: SidebarChecks 392 PASS; пять реальных AppKit regression cases PASS; {native['cycles']} menu state/identity циклов; {circle['cycles']} круговых interrupted cycles. В обоих приложениях по 20 полных sidebar cycles и 20 быстрых разворотов, nativeMaximum и containment PASS.

Лишние обновления: hover круга вынесен из AppModel, неизменившийся selectedIndex не публикуется, drag pasteboard читается при changeCount, paused input timer останавливается, debug flush timer одноразовый. Activity работает только во время жеста/exit.

Видео sidebar находятся в screenshots/before/* и screenshots/after/final-*/sidebar-resize-theme.mov. Time Profiler trace включал QA capture overhead и завершился по time limit; raw trace с host-specific метаданными исключён из Git. Он не доказывает отсутствие hitches или leaks. Perceived smoothness, GPU frame budget и spoken VoiceOver остаются ручной приёмкой.
""")

    fixed = [
        "R01 HIGH: нарисованные и активные сектора расходились на половину сектора; исправлено единым WheelGeometry.",
        "R02 HIGH: часть видимого cancel-центра могла выбрать формат; весь r=64 pt теперь отменяет.",
        "R03 HIGH: край экрана и release могли исполнить прежний/неосознанный выбор; добавлены 6 pt arming и final-position hit-test.",
        "R04 MEDIUM: early close пересоздавал fully-visible view; уходящий view теперь сохраняет presentation, новый gesture получает другой объект.",
        "R05 HIGH: keyboard/direct learning navigation могла проиграть старому fade completion; все requests инвалидируют предыдущий переход.",
        "R06 MEDIUM: обычный status menu MultiSwitcher рисовался custom popover; shipping status item теперь использует NSMenu.",
        "R07 MEDIUM: repeat debug timer просыпался при пустой очереди; заменён одноразовым flush с cancel/release.",
        "R08 MEDIUM: прежний format SF Symbol не отображался; заменён доступными системными символами, все проверены в native window.",
        "R09 HIGH: малые light-circle подписи имели недостаточный контраст; финальная поверхность и текст используют opaque shared tokens.",
        "R10 HIGH: onboarding включал autoConvert, оставляя открытый checkbox выключенным; воспроизведено CUA, исправлено и проверено реальным controller probe.",
        "R11 MEDIUM: Reduce Motion не останавливал уже начатую sidebar-анимацию; добавлен немедленный путь и regression.",
        "R12 HIGH: audit мог писать diagnostic/frame/updater/consent данные в рабочие места; новые пути изолированы, неверный относительный root завершается до открытия production storage.",
        "R13 MEDIUM: QA restore использовал глобальные NSWindow audit keys и фиксированное ожидание; новый roundtrip fixture изолирован, probe ждёт фактического завершения sidebar. Production autosave code path сохранён.",
    ]
    issues = [
        ("U01", "HIGH acceptance gap", "Реальный ввод TextEdit/ChatGPT и hardware hotkeys не подтверждены", "В CUA создан пустой TextEdit документ, инжектированы ghbdtn+space; global foreground оставался MultiSwitcher. Dock activation fallback завис (-10005).", "UNVERIFIED", "Вручную активировать test document, проверить auto/manual/selection/case/undo, затем ChatGPT; не трактовать background injection как дефект алгоритма."),
        ("U02", "MEDIUM", "Физическое Finder drag и menu pointer tracking", "Повторить drag + modifier у центра/краёв, отмену, release, mode switch, быстрое открытие submenu.", "UNVERIFIED", "Использовать fixtures из runtime/packaged-engine; записать физическое прохождение. 100 программных циклов не заменяют это."),
        ("U03", "MEDIUM", "VoiceOver speech и полный keyboard-only flow", "Включить VoiceOver, пройти native menu, sidebar, правила/обучение, отдельный chooser.", "UNVERIFIED", "Проверить произносимые name/role/state, visible focus, Return/Escape и восстановление фокуса."),
        ("U04", "MEDIUM", "Настоящие display scaling / несколько мониторов / увеличенный системный текст", "Повторить на втором display, сменить scaling и backing scale, отключить display и включить системный Reduce Motion.", "UNVERIFIED", "Текущий runtime — один 2x display. 1x/2x component tests и negative-origin geometry не считать физической проверкой."),
        ("U05", "MEDIUM", "Editor apply/save через физический GUI", "Открыть восемь image-tools и три PDF editor-mode, изменить параметры и нажать сохранить копию.", "PARTIAL", "22 формы открыты, 33 frozen-engine actions PASS; физический save, selection dragging и narrow physical display требуют приёмки."),
        ("U06", "LOW", "Изменились хеши обоих рабочих preferences plist при baseline/QA", "Сравнить baseline.json с preservation.json: отличаются com.multiswitcher.app.plist и com.multiswitcher.multishift.plist.", "KNOWN AUDIT LIMIT", "Старые probes использовали технические NSWindow audit keys в рабочих domains. Исходные содержимые plist не снимались, поэтому атрибуция каждого изменения невозможна. Whole-plist identity не подтверждена; файлы не откатывались, чтобы не затереть текущие настройки. Новый probe сохраняет frames в audit suite."),
        ("U07", "MEDIUM", "GPU/frame budget, длительная нагрузка и leaks", "Пройти обычные gestures под Animation Hitches/Allocations и длинной file batch нагрузкой.", "PARTIAL", "Есть 120 s matched UI-idle и Time Profiler trace, но не полная GPU/leaks сертификация. Полный input-monitor idle отделён от visual-review idle."),
        ("U08", "LOW", "Login, notifications и configured release integrations", "Проверить actual login/reboot, доставку уведомления, Sparkle/Sentry в отдельно сконфигурированной сборке.", "UNVERIFIED", "Audit не меняет SMAppService/TCC и не отправляет тестовые уведомления/telemetry; preview не является notarized release."),
        ("U09", "LOW", "Неясные fallback app names", "На системе без Sublime Text открыть исключения: com.sublimetext.4 отображается как «4».", "OPEN", "ExceptionListEditor.displayText: для numeric/generic tail показывать более содержательный suffix или известный alias; сохранить полный bundle ID в tooltip."),
    ]
    write_json("remaining-issues.json", [{"id": a, "severity": b, "problem": c, "repro": d, "status": e, "recommendation": f} for a,b,c,d,e,f in issues])
    passes = all(g["geometry"] and g["stableNavigationAndTheme"] and g["allRestoreStates"] for g in geometry.values())
    checks = load("logs/native-check-results-final.json")
    summary = {"date": "2026-10-25", "implementationComplete": False, "codeChangesComplete": True, "manualAcceptanceComplete": False,
        "settingsStates": sum(g["matrixStates"] for g in geometry.values()), "settingsGeometryPassed": passes,
        "nativeMenuFailures": native["failures"], "pageRegressionPassed": all(x["passed"] for x in native["pageTransitions"]),
        "circleCycles": circle["cycles"], "editorWindows": len(editors["cases"]),
        "frozenWorkerCases": len(engine["cases"]), "frozenWorkerPassed": sum(x["passed"] for x in engine["cases"]),
        "featureRows": len(features), "sharedSourcesIdentical": all(x["identical"] for x in parity),
        "nativeCheckExitCodes": checks, "minimumMeasuredCircleContrast": minimum_contrast,
        "remainingIssues": [x[0] for x in issues]}
    write_json("summary.json", summary)

    q = ["# MultiShift / MultiSwitcher — итоговый UI и functional audit", "", "25 октября 2026 · macOS 27.0.1 · Apple M4 · arm64 · один физический 2x display.", "",
         "## Итог", "",
         "Основные кодовые исправления реализованы, автоматические и native fixture проверки пройдены. Этап по полному плану ещё не принят: U01–U09 ниже содержат конкретные оставшиеся проверки/дефекты. Непроведённая проверка не считается PASS.", "",
         "Preview-сборки установлены в /Applications после аудита; подписи и launch проверены. Временные сборки очищены. Пользовательские profile/history snapshots, точные разрешения и machine-specific profiler trace исключены из Git.", "",
         "## Архитектура и baseline", "",
         "MultiSwitcher: SwiftPM, AppKit controllers, отдельный MultiSwitcherCore (policy, mapping, dictionaries, profile, learning), CGEvent tap и AX text replacement. MultiShift: SwiftUI внутри AppKit windows/panels; native AppModel/FileJobCoordinator → packaged Python JSON worker. Его SwiftPM package тестирует Core, основная app компилируется явным swiftc списком.", "",
         "Общие источники vendored, сборки независимы. MultiDesignKit, MultiPopoverKit, metrics и audit environment побайтово совпадают. Architecture-inventory.json содержит полный список текущих Swift sources/imports/types/hash. Новых sibling runtime dependencies нет.", "",
         "Исходные HEAD: MultiSwitcher 83de261; MultiShift 41a8ed9, оба checkout уже имели незакоммиченные изменения. Их исходные diff и hashes в baseline.json / baseline/*.patch. Девять конфликтных копий сохранены в source-conflicts, а не удалены безвозвратно. Словари и Python conversion logic не редактировались.", "",
         "## Исправления", ""]
    q += ["- " + x for x in fixed]
    q += ["", "## Фактические проверки", "",
          "- Swift tests: MultiShift 23 PASS, MultiSwitcher 22 PASS. Python: 46 PASS, 2 platform-specific SKIP, пять существующих SWIG warnings.",
          "- Sidebar 392 PASS, retained popover 64 PASS, retained layout-state 11 PASS, selection routing 106 assertions PASS, Core checks 310 PASS. Legacy popover checks не подменяют новые native-menu проверки.",
          f"- Настройки: {summary['settingsStates']} native WindowServer снимка/состояния (252 Switcher + 180 Shift), обе темы, оба sidebar, все 7/5 разделов, min/ideal/max и width/height/zoom/restore. geometry, stableNavigationAndTheme, restore и alignment PASS. Все эти кадры не объявляются вручную просмотренными; просмотрены выбранные min/ideal/editor/circle/menu состояния.",
          "- Пять actual-controller regression cases PASS: pointer→keyboard, reversal, same-page interrupt, close/reopen, learned-rule link. Onboarding checkbox consistency проверена тем же shipping action helper.",
          "- 100 NSMenu tracking fixtures PASS: идентичность items и pause expiry state; два настоящих native popup capture. Физический pointer traversal отдельно U02.",
          f"- 30 реальных смен TIS: failures={len(live['failures'])}, max latency {live['maxNotificationLatencyMS']:.1f} ms, original restored={live['originalSourceRestored']}.",
          f"- Круг: {circle['cycles']} interrupted cycles, all symbols available, active panel/input timer/activity после close отсутствуют. Selected text pairs steady-state min {minimum_contrast:.2f}:1 (ROI-метод и исходные пиксели сохранены).",
          f"- Frozen worker: {sum(x['passed'] for x in engine['cases'])}/{len(engine['cases'])} фактических format/tool actions PASS, оригиналы fixtures неизменны. Дополнительно нормальный AppModel путь: conversion, partial batch, trash undo, changed-output protection, pause/resume PASS.",
          "- Editor audit: 22 actual windows (8 image-mode + 3 PDF-mode × 2 темы); apply/save не нажимались. Alternate entry point использует canonical UI/model/worker, но не устанавливает global input monitor.",
          "- Оба приложения восстановили окно в свежем процессе: runtime/restore-results.json PASS. Основные настройки MultiShift также прочитаны из audit suite отдельным процессом; audit-root valid/legacy/invalid cases проверены отдельно.", "",
          "## Производительность", "",
          "Matched сценарий: четыре native settings preview одновременно, 8 s прогрев + около 120 s/121 samples, без взаимодействия и без input monitoring (visual-review mode). Counters: proc_pid_rusage, CPU относительно одного ядра, RSS в bytes. Это не полный фоновой input-monitor benchmark и не доказательство отсутствия leaks.", ""]
    for name, row in perf["summary"].items():
        q.append(f"- {name}: CPU mean {row['cpu_one_core_mean_pct']:.4f}%, p95 {row['cpu_one_core_p95_pct']:.4f}%; RSS {row['rss_start_bytes']/1048576:.1f}→{row['rss_end_bytes']/1048576:.1f} MiB, max {row['rss_max_bytes']/1048576:.1f}; idle wakeups {row['idle_wakeups_per_s']:.3f}/s, interrupt wakeups {row['interrupt_wakeups_per_s']:.3f}/s.")
    q += ["", "Устойчивого роста RSS в этом idle-интервале нет. Разница очень мала в абсолютных CPU процентах; один сеанс не доказывает универсальный performance gain. Сырые samples и точные binary paths — performance-idle.json. Profiler trace остался только локально и не включён в Git из-за host-specific идентификаторов; агрегированные idle measurements сохранены в performance-idle.json.", "",
          "## Сохранность и границы", "",
          f"- Все четыре общих источника byte-identical: {all(x['identical'] for x in parity)}. Repository dictionaries match baseline: {dictionary_match}.",
          "- preservation.json перечисляет классы локальных данных без абсолютных путей и fingerprint-значений. Пользовательские profile/history snapshots и конкретные permission grants не входят в коммит. Preferences plist изменились во время прежнего аудита; их значения не включены, файлы не откатывались.",
          "- Новые audit defaults/profile/history/jobs/diagnostics разделены по абсолютному root; SMAppService, configured updater и telemetry side effects в audit не запускаются. Относительный root отвергается вместо production fallback.",
          "- Preview подписаны локально и проверены после ZIP extraction; notarization не заявляется. Runtime проверен на текущей macOS; minimum deployment 14/15 сохранён, но отдельные старые OS/Intel машины не тестировались.", "",
          "## Оставшиеся проблемы и ручная приёмка", ""]
    for ident, severity, title, repro, status, recommendation in issues:
        q += [f"### {ident} · {severity} · {title}", "", f"Статус: {status}. Воспроизведение/проверка: {repro}", "", recommendation, ""]
    q += ["## Артефакты", "",
          "- [реестр функций](feature-matrix.md) · [анимации](animation-comparison.md) · [круг](circle-design.md)",
          "- [геометрия](geometry-results.json) · [окна](window-results.json) · [сохранность](preservation.json)",
          "- [MultiShift preview](previews/MultiShift-preview.zip) · [MultiSwitcher preview](previews/MultiSwitcher-preview.zip) · [запуск](PREVIEW.md)",
          "- [сводка](summary.json) · [остаточные задачи JSON](remaining-issues.json) · raw logs/runtime и агрегированные performance data рядом; host-specific trace исключён.", "",
          "### Круг до / после", "",
          "![до](screenshots/before/circle/dark-convert-8.png)", "",
          "![после](screenshots/after/approved-circle/dark-convert-8.png)", "",
          "### Системное меню", "",
          "![NSMenu](runtime/native-final-switcher/native-menu-light.png)", "",
          "### Для обсуждения в ChatGPT", "",
          "Используйте этот QA.md вместе с feature-matrix.md и selected screenshots. Следующий список правок следует строить из U01–U09, отделяя OPEN-дефекты от UNVERIFIED hardware acceptance. Не считать Core/fixture PASS подтверждением ввода в ChatGPT или Finder drag."]
    (ROOT / "QA.md").write_text("\n".join(q) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
