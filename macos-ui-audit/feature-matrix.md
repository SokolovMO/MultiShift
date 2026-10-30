# Реестр MultiSwitcher

25 октября 2026. Наличие кода не означает подтверждённую работу. Core/fixture PASS не заменяет live input.

Отдельные состояния: реализована, способ проверки, подтверждённая работа, ошибка и оставшаяся непроверенная часть. U-коды раскрыты в QA.md.

| ID | Функция | Реализована | Проверена | Работает | Ошибка | Не удалось проверить | Доказательство |
|---|---|---|---|---|---|---|---|
| SW01 | включение/выключение приложения | да | native menu / UI | PASS на fixture; ввод U01 | — | U01 | runtime/native-final-switcher/native-results.json |
| SW02 | ручная конверсия последнего слова | да | Core / selection harness | алгоритм PASS | — | U01: реальные клавиши | logs/selection_conversion-final.log |
| SW03 | конверсия выделенного текста | да | Core / selection harness | алгоритм и routing PASS | — | U01: AX/вставка в сторонние поля | logs/selection_conversion-final.log |
| SW04 | конверсия всей строки | да | код / Core | Core PASS; OS-доставка не подтверждена | — | U01 | logs/switcher-core-checks.log; logs/switcher-tests-final.log |
| SW05 | автоматическая коррекция на границе слова | да | Core / настройки UI | Core PASS; live ввод не подтверждён | исправлена рассинхронизация onboarding | U01 | logs/switcher-core-checks.log; logs/switcher-tests-final.log; runtime/cua-results.json |
| SW06 | защита URL, кода, mixed text, acronym и коротких слов | да | Core / selection harness | PASS на наборах | — | реальные приложения U01 | logs/selection_conversion-final.log |
| SW07 | smart conversion | да | Core / selection harness | PASS на наборах | — | U01 | logs/selection_conversion-final.log |
| SW08 | определение направления по тексту | да | Core / selection harness | PASS на наборах | — | U01 | logs/selection_conversion-final.log |
| SW09 | смена регистра | да | Core / selection harness | routing PASS | — | U01: реальный hotkey | logs/selection_conversion-final.log |
| SW10 | отмена и восстановление точного текста | да | Core | политики PASS | — | U01: реальный undo/clipboard | logs/switcher-core-checks.log; logs/switcher-tests-final.log |
| SW11 | отслеживание активной раскладки и badge | да | 30 реальных TIS переключений | PASS; исходная раскладка восстановлена | — | физический системный hotkey отдельно | runtime/live-layout/live-layout-results.json |
| SW12 | выбор пары раскладок / автоопределение | да | код / TIS / Core | TIS пары PASS | — | ручная настройка всех пар | logs/switcher-core-checks.log; logs/switcher-tests-final.log; runtime/live-layout/live-layout-results.json |
| SW13 | автопереход языка по порогу слов | да | Core | политика PASS | — | U01 | logs/switcher-core-checks.log; logs/switcher-tests-final.log |
| SW14 | запоминание раскладки по приложениям | да | Core | память и политика PASS | — | U01: переключение реальных приложений | logs/switcher-core-checks.log; logs/switcher-tests-final.log |
| SW15 | триггер Option/Caps Lock/модификатор | да | код | не подтверждено в live UI | — | U01 | KeyboardMonitor.HotkeyConfig / SettingsManager / HelpWindowController |
| SW16 | ограничение правой клавишей | да | код | не подтверждено в live UI | — | U01 | KeyboardMonitor.HotkeyConfig / SettingsManager / HelpWindowController |
| SW17 | двойной тап | да | код | не подтверждено в live UI | — | U01 | KeyboardMonitor.HotkeyConfig / SettingsManager / HelpWindowController |
| SW18 | отдельный hotkey смены раскладки | да | код | не подтверждено в live UI | — | U01 | KeyboardMonitor.HotkeyConfig / SettingsManager / HelpWindowController |
| SW19 | hotkey смены регистра | да | код | не подтверждено в live UI | — | U01 | KeyboardMonitor.HotkeyConfig / SettingsManager / HelpWindowController |
| SW20 | конфликты и отключение hotkeys | да | код | не подтверждено в live UI | — | U01 | KeyboardMonitor.HotkeyConfig / SettingsManager / HelpWindowController |
| SW21 | пауза до возобновления | да | native menu / Core | состояния PASS | — | U01: ввод в паузе | logs/switcher-core-checks.log; logs/switcher-tests-final.log; runtime/native-final-switcher/native-results.json |
| SW22 | пауза 15/60 минут и истечение срока | да | Core / native fixture | срок и обновление существующих menu items PASS | — | реальный длительный таймер / restart | logs/switcher-core-checks.log; logs/switcher-tests-final.log; runtime/native-final-switcher/native-results.json |
| SW23 | исключения только автокоррекции | да | Core / реальные окна | политика PASS; список отрисован | — | U01: add/remove и ввод | logs/switcher-core-checks.log; logs/switcher-tests-final.log; screenshots/after/final-multiswitcher |
| SW24 | полное отключение действий для приложения | да | Core / реальные окна | политика PASS | — | U01 | logs/switcher-core-checks.log; logs/switcher-tests-final.log |
| SW25 | режимы приложения: обычно / вручную / выключено | да | native menu / Core | fixture PASS | — | физическое применение к сторонним приложениям | logs/switcher-core-checks.log; logs/switcher-tests-final.log; runtime/native-final-switcher/native-results.json |
| SW26 | защищённые приложения и Secure Input | да | код / Core | проверены политики | — | U01: реальное защищённое поле; TCC не изменялись | logs/switcher-core-checks.log; logs/switcher-tests-final.log |
| SW27 | ChatGPT через общие механизмы приложений | да | код | не подтверждено в ChatGPT | — | U01: composer не затрагивался; отдельного раздела ChatGPT нет | ApplicationExclusionPolicy / AppDelegate |
| SW28 | словари RU/EN и динамические keyboard maps | да | реальные словари / Core | PASS на наборах | — | AppleSpell и live input отдельно | logs/selection_conversion-final.log |
| SW29 | тематические словари | да | Core / реальные packaged wordlists | PASS на наборах | — | ручное переключение UI и перезапуск | logs/selection_conversion-final.log |
| SW30 | never/always convert списки | да | Core | PASS | — | live input U01 | logs/switcher-core-checks.log; logs/switcher-tests-final.log |
| SW31 | правила exact/prefix/contains/regex и замены | да | Core / native rule probe | fixture PASS | — | ручное создание/import/export U01 | logs/switcher-core-checks.log; logs/switcher-tests-final.log; logs/switcher-final-geometry.log |
| SW32 | поиск, выбор и клавиатура списка правил | да | native controller probe | PASS на fixture | — | VoiceOver U03 | logs/switcher-final-geometry.log |
| SW33 | импорт профиля Punto и provenance | да | Core | PASS на fixture-файлах | — | настоящий пользовательский импорт не выполнялся | logs/switcher-core-checks.log; logs/switcher-tests-final.log |
| SW34 | экспорт/импорт пользовательских правил | да | Core codec / код UI | codec PASS | — | file panels и ручной roundtrip | logs/switcher-core-checks.log; logs/switcher-tests-final.log |
| SW35 | восстановление удалённых Punto-правил | да | Core | PASS на fixture | — | ручное действие UI | logs/switcher-core-checks.log; logs/switcher-tests-final.log |
| SW36 | профиль: atomic save, backup, восстановление | да | Core / isolated fixture | fixture PASS; host profile contents omitted | — | полный пользовательский disaster recovery не запускался | logs/switcher-core-checks.log; logs/switcher-tests-final.log; preservation.json |
| SW37 | обучение по отмене автоматических исправлений | да | Core | PASS на fixture | — | U01: реальные циклы отмены | logs/switcher-core-checks.log; logs/switcher-tests-final.log |
| SW38 | кандидаты ручного обучения и подтверждение | да | Core / native learning probe | fixture PASS | — | U01: реальный Option и подтверждение | logs/switcher-core-checks.log; logs/switcher-tests-final.log; logs/switcher-final-geometry.log |
| SW39 | забыть / не исправлять / undo обучения | да | Core / native learning probe | fixture PASS | — | физические действия и restart | logs/switcher-core-checks.log; logs/switcher-tests-final.log |
| SW40 | переход из обучения к правилу | да | реальный AppKit controller | PASS после прерывания fade | исправлен обход отмены переходов | физический клик отдельно | runtime/native-final-switcher/native-results.json |
| SW41 | caret-индикатор | да | код | не подтверждено в live UI | — | U01 | CaretIndicator / AppDelegate.syncCaretIndicator |
| SW42 | звук клавиш | да | код | не подтверждено в live UI | — | U01 | KeyboardMonitor / SettingsManager.keySound |
| SW43 | уведомление Secure Input | да | код / native fixture | отображение проверено | — | U01: реальный защищённый ввод | SecureInputNotice / screenshots/after/final-multiswitcher |
| SW44 | remote desktop beta | да | код / Core политики | не подтверждено end-to-end | — | нет второй remote-сессии | KeyboardMonitor / configureIconRefreshFallback |
| SW45 | скрытие tray и повторное открытие | да | код | не подтверждено физически | — | reopen скрытой иконки | AppDelegate.applicationShouldHandleReopen |
| SW46 | автозапуск | да | код / чтение текущего состояния | регистрация не проверялась | — | U08: audit не меняет SMAppService | SettingsManager.launchAtLogin / syncLoginItem |
| SW47 | разрешения и фоновый запуск мониторинга | да | локальный runtime check | проверка выполнена; конкретные grant values omitted | — | доставка hardware input U01 | runtime/input-switcher/permission-runtime.json |
| SW48 | помощник разрешений | да | код / native fixture | отображение доступно | — | не выдавались и не сбрасывались реальные TCC-разрешения | PermissionsGuideWindowController |
| SW49 | каналы и проверка обновлений | да | код / configured guard | release-интеграция не проверена | — | U08: Sparkle/configured endpoint выключены в preview | UpdateChecker / SparkleUpdateChecker |
| SW50 | crash consent и редактирование диагностики | да | Core redaction / код | redaction PASS; SDK не активирован | — | U08: Sentry не включён | logs/switcher-core-checks.log; logs/switcher-tests-final.log; CrashReporter |
| SW51 | диагностический лог | да | код / build | однократный flush вместо вечного таймера | исправлен пустой повторяющийся timer | длительный debug-сеанс не профилировался отдельно | KeyboardMonitor.RSLogWriter |
| SW52 | язык интерфейса и темы | да | реальные окна обеих тем | PASS выбранных состояний | — | все переводы и длинные строки вручную не просмотрены | geometry-results.json |
| SW53 | сохранение geometry после перезапуска | да | два отдельных процесса | PASS обоих приложений | — | production autosave не перезаписывался новым probe | runtime/restore-results.json |
| SW54 | системное status bar меню | да | реальный NSMenu + 100 fixture циклов | PASS состояния/identity и native capture | заменён custom popover | U02: physical pointer/keyboard tracking | runtime/native-final-switcher/native-results.json |
| SW55 | навигация и прерываемые переходы | да | native controller + CUA | 5 регрессий PASS; CUA переход подтверждён | исправлены stale completion и onboarding state | U03: spoken VoiceOver | runtime/native-final-switcher/native-results.json |
| SW56 | Reduce Motion во время sidebar-анимации | да | native SidebarChecks | PASS, немедленное завершение | — | реальный системный toggle и физический дисплей U04 | logs/sidebar_layout-final.log |

## MultiShift: дополнительный реестр

- 10 image targets и PDF/DOCX/TXT: фактический frozen-worker прогон, все 33 format/tool cases PASS; оригиналы неизменны.
- Image tools: compress, resize, crop, edit, annotate, redact, background, metadata — CLI outputs проверены; реальные формы открыты в обеих темах.
- PDF tools: compress, split, rotate, merge, protect, extract, metadata — CLI outputs проверены; формы compress/protect/metadata открыты в обеих темах.
- Обычный AppModel/FileJobCoordinator путь: JPG, partial batch, trash-only undo, защита изменённого output, pause/resume — PASS на собственных fixtures.
- Круг: геометрия и 6 pt arming проверены; 100 прерываний, все SF Symbols, обе темы — fixture PASS. Finder hardware drag/отпускание/Escape остаются U02.
- История, Finder actions, notification permissions, actual login и клавиатурный chooser: реализация сохранена; физическая приёмка не завершена.
- 22 editor windows открыты, preview отрисован в выбранных просмотренных снимках; apply/save клики в GUI не выполнялись. CLI tool PASS не равен GUI save PASS.
