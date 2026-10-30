# Круг MultiShift

Панель 400×400 pt, внешняя поверхность r=184 pt, cancel r=64 pt, центр/границы/подписи/hit-test используют WheelGeometry. 10 форматов остаются в одном кольце, инструменты сохраняют собственный режим и стабильные action IDs.

Цель — монохром без glow: общие непрозрачные neutral tokens, 1/backingScale разделители, SF Symbols 18 pt, подписи 11 pt. Непрозрачная поверхность сохраняет читаемость над любым desktop; глубину дают небольшой shadow и центральная поверхность. Центр всегда явно обозначает отмену и Escape.

Отличия от baseline: исправлены half-sector offset и активная часть видимого центра; первый выбор требует 6 pt движения; final cursor hit-test выполняется перед отпусканием; mode change не отменяет queued entrance. Outgoing hosting view сохраняет текущую анимацию и отделённый presentation object, новый вызов не мутирует уходящую панель.

Появление 140 ms (opacity, scale 0.97→1); закрытие 90 ms opacity; hover 100 ms. Выполнение действия не ждёт exit. Во время видимого жеста включена короткая user-initiated activity, позволяющая idle sleep; токен заканчивается после exit, нового постоянного фонового activity нет. Reduce Motion убирает scale.

Фактические результаты: 100 прерванных циклов; activePanelAfterClose=False; inputTimerAfterClose=False; activityAfterClose=False. Все symbols доступны. Минимальное измеренное steady-state соотношение выбранных текстовых пар: 4.80:1; детали в runtime/circle-contrast.json.

Нативные снимки: screenshots/before/circle и screenshots/after/approved-circle. Аппаратный Finder drag, edge release, Escape и несколько физических мониторов не сертифицированы fixture-прогоном.
