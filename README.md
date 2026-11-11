# MultiShift

macOS-приложение для конвертации и обработки копий файлов прямо из Finder:
удерживайте файл, нажмите выбранную клавишу и отпустите его на нужном действии.
Оригиналы не перезаписываются. Есть пакетная обработка, история, отмена через
Корзину, русский/английский язык и системное/светлое/тёмное оформление.

## Установка

Загрузка DMG с перетаскиванием в «Программы» и команда установки: https://sokolovmo.ru/multishift/ .
macOS 14+, Apple Silicon. Приложение пока без нотарификации Apple: при ручной
установке из DMG/ZIP macOS может потребовать разрешить открытие в настройках безопасности.
Опубликованный установщик проверяет загрузку, устанавливает приложение и снимает
карантин только с проверенной копии MultiShift.

Обновления проверяются автоматически через Sparkle и устанавливаются после
подтверждения. Apple Developer и платная панель для выпуска не требуются.

## Сборка и проверка

Нужны macOS 14+ и Python 3.12.

```sh
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-macos.lock -r requirements.txt
QT_QPA_PLATFORM=offscreen python -m pytest -q
swift test --package-path macos
bash scripts/build_macos.sh
```

Локальная сборка: `dist/MultiShift.app`, без обновлений по умолчанию.
Для управляемых папок можно задать `MULTISHIFT_OUTPUT_DIR=/tmp/MultiShift-build`.
Самостоятельная сборка и публикация: [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).
`install-mac.sh` в исходниках — шаблон; готовый `install.sh` создаёт сборщик релиза.

## Лицензии

[LICENSE](LICENSE), [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
Каждый релиз содержит соответствующий архив исходников и лицензии компонентов.

## English

MultiShift converts and edits copies of files using a Finder action menu.
Requires macOS 14+ and Apple Silicon. Download from https://sokolovmo.ru/multishift/ .
The app is not Apple-notarized. Updates use Sparkle and Ed25519-signed archives
and feeds. No Apple Developer account or release dashboard is required to build
and publish; see the distribution guide above.
