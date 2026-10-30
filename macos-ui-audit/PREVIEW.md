# Проверка preview

ZIP содержат отдельные локальные сборки. Установленные приложения в `/Applications` не заменялись. Подписи проверены после распаковки; notarization не заявляется. macOS может запросить разрешения для новой копии.

Для просмотра настроек без мониторинга ввода распакуйте ZIP, затем запустите бинарник из Terminal с отдельным абсолютным каталогом. Пример для MultiShift:

```sh
MULTI_ECOSYSTEM_REVIEW=<TMP>/multishift-preview-review \
MULTI_ECOSYSTEM_INTERACTIVE=1 \
/absolute/path/MultiShift.app/Contents/MacOS/MultiShift
```

Для MultiSwitcher используйте аналогичную команду с другим каталогом и бинарником `MultiSwitcher.app/Contents/MacOS/MultiSwitcher`. Копии общих компонентов находятся внутри каждого приложения; соседний checkout не требуется.

Для функционального запуска с обычным мониторингом завершите установленную копию того же приложения, затем используйте **другую** переменную:

```sh
MULTI_AUDIT_DATA_ROOT=<TMP>/multishift-functional-preview \
/absolute/path/MultiShift.app/Contents/MacOS/MultiShift
```

Для MultiSwitcher аналогично замените путь и каталог. Сначала настройте разрешения и включите нужные функции в этом отдельном профиле. Audit-режим не включает настоящий автозапуск, телеметрию и обновление. Без audit-переменной обычный запуск использует прежнее пользовательское хранилище. После проверки завершите preview и снова откройте установленную копию.

Готовые изображения круга находятся в `screenshots/after/approved-circle`, меню — в `runtime/native-final-switcher`. Физические сценарии для завершения приёмки перечислены в `QA.md`: автоматические fixtures не заменяют Finder drag, ввод в ChatGPT и VoiceOver.
