# Сравнение анимаций

Общий sidebar уже был побайтово одинаковым: 208/60 pt, одна непрерывная phase, критически затухающий профиль 260 ms, продолжение velocity при развороте. Разницу качества нельзя приписывать разным sidebar springs.

MultiShift меняет содержимое SwiftUI через opacity transition; MultiSwitcher использовал последовательный AppKit fade 70+90 ms и мог применить старый completion после keyboard/immediate запроса. Теперь каждый запрос инвалидирует прежний, opacity продолжается от presentation, прямой переход из обучения тоже использует общий путь.

Общие значения: curve (0.23,1,0.32,1), navigation 160 ms, hover 100 ms, sidebar 260 ms. Custom toggle MultiSwitcher использует ту же standard curve вместо отдельной недозатухающей spring. Keyboard navigation мгновенна. Системный NSMenu использует собственное движение macOS.

Reduce Motion теперь прерывает уже активный sidebar timer, а не только новые переходы; это проверяется отдельными SidebarChecks. Системный accessibility notification подписан через NSWorkspace.notificationCenter. Circle presence/exit/hover описаны в circle-design.md.

Результаты: SidebarChecks 392 PASS; пять реальных AppKit regression cases PASS; 100 menu state/identity циклов; 100 круговых interrupted cycles. В обоих приложениях по 20 полных sidebar cycles и 20 быстрых разворотов, nativeMaximum и containment PASS.

Лишние обновления: hover круга вынесен из AppModel, неизменившийся selectedIndex не публикуется, drag pasteboard читается при changeCount, paused input timer останавливается, debug flush timer одноразовый. Activity работает только во время жеста/exit.

Видео sidebar находятся в screenshots/before/* и screenshots/after/final-*/sidebar-resize-theme.mov. Time Profiler trace включал QA capture overhead и завершился по time limit; raw trace с host-specific метаданными исключён из Git. Он не доказывает отсутствие hitches или leaks. Perceived smoothness, GPU frame budget и spoken VoiceOver остаются ручной приёмкой.
