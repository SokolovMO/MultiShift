# MultiShift

**MultiShift** is a macOS application: hold a file in Finder, press the chosen modifier key, and drop it on a radial action to convert or edit a copy.

MultiShift provides a radial menu, Russian and English interfaces, system/light/dark appearance, batch feedback and operation history. Original files are not overwritten.

## Состояние проекта

Первая версия готовится для macOS. В репозитории есть исходный код и сборка для локальной проверки. Публичных установочных сборок пока нет.

Интерфейс запускается на русском языке. Язык и оформление можно поменять в настройках:

- русский и английский;
- оформление macOS, светлое или тёмное;
- форматы изображений, PDF, Word и текста;
- обработка нескольких файлов с отчётом о частичных ошибках;
- отмена результата перемещает созданные файлы в системную Корзину.

MultiShift — независимое приложение с отдельным bundle ID, LaunchAgent, настройками и папкой результатов.

## Проверка из исходников

Нужны macOS 14 или новее и Python 3.12.

```sh
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-macos.lock -r requirements.txt
QT_QPA_PLATFORM=offscreen python -m pytest -q
bash scripts/build_macos.sh
```

Приложение появится в `dist/MultiShift.app`. Если репозиторий хранится в iCloud Drive или другой управляемой папке, задайте для сборки отдельный локальный путь, например `MULTISHIFT_OUTPUT_DIR=/tmp/MultiShift-build bash scripts/build_macos.sh`. Локальная сборка получает временную ad-hoc подпись для проверки, но не подписана Developer ID и не нотарифицирована. Для публичных загрузок настроена отдельная сборка с подписью Developer ID и нотарификацией Apple. Релизный workflow завершится ошибкой, если данные подписи не настроены; неподписанные сборки не будут публиковаться вместо неё.

`install-mac.sh` ничего не устанавливает. Используйте локальную сборку или подписанный DMG MultiShift после публикации.

## Лицензии

Лицензии используемых компонентов и библиотек включаются в собранное приложение. Смотрите [LICENSE](LICENSE) и [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## English

MultiShift is a macOS application with a radial file-action menu, Russian/English localization, system/light/dark appearance, batch feedback, operation history and trash-only undo for generated files.

The first release is being prepared. No public installer is available yet. Build and run the checks with the commands above. The release workflow requires Developer ID signing and Apple notarization credentials and fails closed if they are missing.

