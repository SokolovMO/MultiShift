# Homebrew и реальные обновления — 2026-11-07

Финальный выпуск: 0.3.0 (6), ZIP SHA256
`d3ed90ab23ebca9668fb97fe13cff619bc2a69d6f4df0556b07f96df381798cc`.
Tap: https://github.com/SokolovMO/homebrew-apps (ba0eb01).

- Homebrew 7.0.11: установка, повторная установка и upgrade 4→6 в отдельном каталоге
  прошли. Без согласия карантин остаётся; с HOMEBREW_MULTI_APPS_ALLOW_UNNOTARIZED=1
  проверяется подпись и снимается карантин только с MultiShift. Обычная переменная
  без префикса HOMEBREW_ фильтруется самим brew и не подходит для согласия.
- Реальные Sparkle 3→4→5→6 с проверкой, загрузкой, подтверждением и перезапуском
  прошли. Финальный executable совпадает с релизным; codesign --deep --strict PASS.
- Host bundle теперь объявляет ru/en: предложение 5→6, текст выпуска, загрузка и
  «Установить и перезапустить» показаны на русском. Исходники доступны по ссылке.
- Финальная рабочая копия в /Applications принята Homebrew через --adopt без замены.
- История операций семантически прежняя; JSON форматирование может меняться.
  В настройках изменились только NSWindow Frame SUUpdateAlert2 и SULastCheckTime.
- Пять release-тестов (включая настоящие Ed25519 подписи и отказы при подмене)
  прошли. Новый тест воспроизвёл отсутствующие CFBundleLocalizations до исправления.
- Публичные latest/appcast совпали с проверенной раздачей. Сборщик проверил ZIP,
  смонтированный DMG и native/engine selftest. Конфигурация nginx и 10 остальных
  маршрутов не изменились; proxy не перезапускался и не перезагружался.
- Подробные логи и резервные копии: /tmp/multi-homebrew-qa/ .

Проверка относится к этому Mac. Нотарификации Apple нет; чистый Mac, все версии
macOS и установка во время активной конвертации отдельно не проверялись.

---

# Публикация 2026-11-06

- MultiShift 0.3.0, build 2, arm64, минимум macOS 14.
- Раздача: https://sokolovmo.ru/multishift/ .
- SHA256 ZIP: `b13f5daf8111bee64bfebc83f84eee2b8fa1c940a54954c166581a77534d8c90`.
- Python: 50 passed, 3 skipped; 5 известных предупреждений SWIG.
- Swift/XCTest: 25 passed с выбранным Xcode developer directory.
- Собран updater-enabled bundle, проверены подписи и native/engine selftest.
- ZIP распакован и повторно проверен codesign --deep --strict и native selftest.
- Реальными Sparkle tools проверены подписи ZIP/appcast и отклонение подмены.
- Публичный install.sh выполнен с --verify-only: фактическая HTTPS-загрузка ZIP,
  размер, SHA256, допустимые пути/links архива, bundle ID, build, updater key/URL,
  codesign и native selftest прошли. /Applications не менялся.
- Публичные appcast/latest/install побайтово совпали с подготовленными файлами;
  подпись скачанного appcast проверена. Страница и исходники доступны по HTTPS.
- Вёрстка проверена на 1440/768/390 px. Для страницы установки сознательно исключены
  декоративные фото, видео и анимация; действие — копирование команды установки.
- На Vyrex подтверждён существующий системный nginx. Сделан backup конфигурации
  `/var/backups/multishift/20261106T021319Z/nginx-sokolovmo.ru`.
  Добавлен только /multishift/, nginx -t прошёл до/после, выполнен reload nginx.
- После публикации у 13 прежних маршрутов совпали статусы и SHA256 ответов:
  корень, workshop, finbot, site1–site6, v6, codex, finbot subdomain, ai-galina-course.
- Текущая папка: `/var/www/multishift/releases/build-2-b13f5daf8111bee6`.

Не подтверждены: замена приложения в /Applications, ответ installer health после
полной установки, обновление A → B через UI Sparkle, физические Finder/VoiceOver/
несколько дисплеев и проверка всех поддерживаемых macOS. Тест второй копии завершён
штатной защитой от дубликатов: на Mac уже работает /Applications/MultiShift.app.
Работающий экземпляр не завершался и не заменялся. Это не считается успешной
проверкой installer health или обновления A → B.

Локальные подробные логи: /tmp/multishift-public-build2.log,
/tmp/multishift-independent-swift-xcode.log. Исходные изменения не закоммичены.
