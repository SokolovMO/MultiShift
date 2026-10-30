"""Small, stable-key UI translation layer for MultiShift.

Internal action identifiers stay in English (for example ``tool:Compress``); only
the text shown to a person is translated. This keeps routing and saved settings
independent of the selected language.
"""
from __future__ import annotations

import re
from typing import Any

LANGUAGES = [("ru", "Русский"), ("en", "English")]
_language = "ru"

RU = {
    # Main menu and radial menu
    "Enabled": "Включено",
    "press {trigger} while dragging a file": "нажмите {trigger}, удерживая файл",
    "Open a file…": "Открыть файлы…",
    "Choose file(s) for MultiShift": "Выберите файлы для MultiShift",
    "Settings…": "Настройки…",
    "How to use": "Как пользоваться",
    "About MultiShift": "О MultiShift",
    "Quit MultiShift": "Завершить MultiShift",
    "Convert": "Форматы",
    "Tools": "Инструменты",
    "Compress": "Сжать",
    "Metadata": "Метаданные",
    "Redact": "Скрыть данные",
    "Crop": "Обрезать",
    "Edit": "Обработка",
    "Annotate": "Разметить",
    "Add BG": "Добавить фон",
    "Resize": "Размер",
    "Split": "Разделить",
    "Rotate": "Повернуть",
    "Merge": "Объединить",
    "Protect": "Защитить",
    "Extract": "Извлечь",
    "Drop here": "Перетащите сюда",
    "Images · PDF · Word · Text": "Изображения · PDF · Word · текст",
    "images": "изображений",
    "Can't convert {ext}": "Нет действий для {ext}",
    "Shrink file size": "Уменьшить размер файла",
    "View · remove GPS": "Посмотреть · удалить геоданные",
    "Hide private info": "Скрыть личную информацию",
    "Trim to a ratio": "Обрезать по пропорциям",
    "Crop Image": "Обрезка изображения",
    "Light · colour · rotate": "Свет · цвет · поворот",
    "Arrows · text · steps": "Стрелки · текст · номера",
    "Gradient backdrop": "Градиентный фон",
    "Change dimensions": "Изменить размеры",
    "One PDF per page": "Отдельный PDF для каждой страницы",
    "Turn pages 90°": "Повернуть страницы на 90°",
    "Join into one PDF": "Объединить в один PDF",
    "Add a password": "Установить пароль",
    "Save embedded images": "Сохранить встроенные изображения",
    "Small, universal": "Компактный универсальный формат",
    "Lossless · transparency": "Без потерь · прозрачность",
    "Smallest for web": "Компактный формат для веба",
    "iPhone format": "Формат iPhone",
    "Print · archival": "Печать · архив",
    "Next-gen, tiny": "Современный компактный формат",
    "Uncompressed": "Без сжатия",
    "Document": "Документ",
    "Windows icon": "Значок Windows",
    "Legacy web": "Устаревший веб-формат",
    "Editable Word": "Редактируемый документ Word",
    "Plain text": "Обычный текст",
    # Preferences
    "Settings": "Настройки",
    "Close (Esc)": "Закрыть (Esc)",
    "Language": "Язык",
    "Appearance": "Оформление",
    "Output": "Результат",
    "System": "Как в macOS",
    "Light": "Светлое",
    "Dark": "Тёмное",
    "Open the menu with": "Открывать меню клавишей",
    "…pressed while you’re dragging a file": "нажмите её, удерживая файл",
    "Save results": "Сохранять результаты",
    "Next to the original": "Рядом с исходным файлом",
    "In a “MultiShift” subfolder": "В папке «MultiShift»",
    "JPG / WebP quality": "Качество JPG / WebP",
    "PDF → image resolution": "Разрешение PDF → изображение",
    "150 dpi · small": "150 dpi · компактно",
    "200 dpi · balanced": "200 dpi · обычно",
    "300 dpi · print": "300 dpi · для печати",
    "Open MultiShift at login": "Запускать MultiShift при входе",
    "Start MultiShift with Windows": "Запускать MultiShift вместе с Windows",
    "Enable full liquid glass…": "Включить эффект стекла…",
    "Lets the glass refract the windows behind it (Screen Recording permission)":
        "Позволяет стеклу преломлять окна на фоне (нужно разрешение на запись экрана)",
    "MultiShift {version}  ·  originals are never modified":
        "MultiShift {version} · исходные файлы не меняются",
    "Done": "Готово",
    # Welcome
    "Welcome to MultiShift": "Добро пожаловать в MultiShift",
    "Start dragging any file": "Начните перетаскивать файл",
    "in Finder or on the desktop": "в Finder или с Рабочего стола",
    "the glass menu opens right under your cursor": "круговое меню появится у курсора",
    "Drop it on a slice": "Перетащите его на действие",
    "the result is saved next to the original": "результат сохранится рядом с исходным файлом",
    "Tap {trigger} again": "Нажмите {trigger} ещё раз",
    "to switch between Convert and Tools": "чтобы перейти от форматов к инструментам",
    "Optional: allow Screen Recording so the glass can refract the windows behind it (otherwise it shows your wallpaper). MultiShift never saves or sends it.":
        "Можно разрешить запись экрана, чтобы видеть окна сквозь стекло. Иначе будет виден фон рабочего стола. MultiShift не сохраняет и не отправляет изображение экрана.",
    "Allow Screen Recording…": "Разрешить запись экрана…",
    "You're on a Wayland session: the Shift-while-dragging trigger needs X11 (e.g. XFCE). Right-click a file → Open With → MultiShift still works.":
        "Сейчас используется Wayland: сочетание клавиши и перетаскивания работает в X11 (например, XFCE). Открытие через контекстное меню файла доступно.",
    "Open at login": "Запускать при входе",
    "Got it": "Понятно",
    # Common tool controls
    "Reset": "Сбросить",
    "Cancel": "Отмена",
    "Save": "Сохранить",
    "Apply": "Применить",
    "Aspect ratio": "Пропорции",
    "ASPECT RATIO": "ПРОПОРЦИИ",
    "BACKGROUND": "ФОН",
    "EXACT SIZE": "ТОЧНЫЙ РАЗМЕР",
    "SIZE": "РАЗМЕР",
    "PRESETS — PERCENT OR LONGEST SIDE IN PX": "БЫСТРЫЙ РАЗМЕР — ПРОЦЕНТ ИЛИ ДЛИННАЯ СТОРОНА, PX",
    "Background": "Фон",
    "Padding": "Отступ",
    "Corners": "Скругление",
    "Shadow": "Тень",
    "Angle": "Угол",
    "Auto": "Авто",
    "Save with Background": "Сохранить с фоном",
    "Background colour": "Цвет фона",
    "➜ Arrow": "➜ Стрелка",
    "▢ Box": "▢ Прямоугольник",
    "◯ Circle": "◯ Круг",
    "✎ Pen": "✎ Карандаш",
    "▬ Marker": "▬ Маркер",
    "T Text": "T Текст",
    "① Step": "① Шаг",
    "Brightness": "Яркость",
    "Contrast": "Контраст",
    "Saturation": "Насыщенность",
    "Warmth": "Теплота",
    "Sharpness": "Резкость",
    "✦ Auto": "✦ Авто",
    "⇋ Flip": "⇋ По горизонтали",
    "⇵ Flip": "⇵ По вертикали",
    "B&&W": "Ч/Б",
    "1:1": "1:1",
    "4:3": "4:3",
    "16:9": "16:9",
    "9:16": "9:16",
    "4:5": "4:5",
    "quality ≈ {quality}": "качество ≈ {quality}",
    "target {label}": "лимит {label}",
    "quality {quality}": "качество {quality}",
    "≈ {percent}% smaller · {format}": "≈ на {percent}% меньше · {format}",
    "Rotate 90°": "Повернуть на 90°",
    "Double-click the image to reset": "Дважды щёлкните по изображению, чтобы сбросить",
    "Custom colour": "Свой цвет",
    "Copy": "Копировать",
    "Copied ✓": "Скопировано ✓",
    "Copy the result to the clipboard": "Скопировать результат в буфер обмена",
    "Type, then Enter": "Введите текст и нажмите Enter",
    "Undo": "Отменить",
    "Redo": "Повторить",
    "Size": "Размер",
    "Black box": "Чёрный прямоугольник",
    "Pixelate": "Пикселизация",
    "Blur": "Размытие",
    "Drag over anything you want hidden. It's burned into the pixels — it can't be undone in the copy.":
        "Проведите по участку, который нужно скрыть. Изменение будет записано в копию и не подлежит отмене.",
    "Automatic light and colour": "Автоматически настроить свет и цвет",
    "Hold to compare": "Удерживайте для сравнения",
    "Open map": "Открыть карту",
    "⚠  This photo reveals where it was taken.": "⚠  На фото сохранено место съёмки.",
    "Show all {count} fields": "Показать все поля: {count}",
    "Remove location only": "Удалить только геоданные",
    "Remove all metadata": "Удалить все метаданные",
    "Make each file under": "Ограничить размер каждого файла",
    "Quality": "Качество",
    "Target size": "Размер файла",
    "Original size": "Исходный размер",
    "Max 3840 px": "До 3840 px",
    "Max 2560 px": "До 2560 px",
    "Max 1920 px": "До 1920 px",
    "Max 1280 px": "До 1280 px",
    "Max 800 px": "До 800 px",
    "Convert to WebP (usually the smallest)": "Преобразовать в WebP (обычно компактнее)",
    "Original": "Исходное",
    "Free": "Свободно",
    "Compressed": "После сжатия",
    "Already well compressed — try a smaller size or WebP": "Файл уже хорошо сжат. Попробуйте меньший размер или WebP",
    "Keep proportions": "Сохранить пропорции",
    "Presets — percent or longest side in px": "Быстрый размер — процент или длинная сторона, px",
    "Exact size": "Точный размер",
    "Password-protect PDF": "Защитить PDF паролем",
    "Password": "Пароль",
    "Confirm": "Повторите пароль",
    "Show": "Показать",
    "AES-256 encryption. Anyone opening the PDF will need this password.":
        "Шифрование AES-256. Для открытия PDF потребуется этот пароль.",
    "Use at least 4 characters.": "Введите не менее 4 символов.",
    "Passwords don't match yet.": "Пароли пока не совпадают.",
    "Looks good · {strength} password": "Пароль подходит · надёжность: {strength}",
    "weak": "низкая",
    "okay": "средняя",
    "strong": "высокая",
    "No personal metadata found.": "Личные метаданные не найдены.",
    "Field": "Поле",
    "Value": "Значение",
    # App and operation feedback
    "Drag any file and press {trigger}. It lives in the tray.":
        "Перетащите файл и нажмите {trigger}. MultiShift работает в строке меню.",
    "Drag any file, then press {trigger}.": "Перетащите файл и нажмите {trigger}.",
    "MultiShift is already running": "MultiShift уже запущен",
    "Couldn't open {name}": "Не удалось открыть: {name}",
    "Couldn't finish": "Не удалось завершить",
    "No permission to write next to this file. Try a folder you own, or set Settings → Save results → subfolder.":
        "Нет разрешения на запись рядом с файлом. Выберите доступную папку в настройках сохранения.",
    "This file doesn't look like an image MultiShift can read.": "Не удалось прочитать изображение этого формата.",
    "The file was moved or deleted.": "Файл перемещён или удалён.",
    "Undone": "Отменено",
    "Undo incomplete": "Отмена выполнена не полностью",
    "Trash": "Корзину",
    "Open in Finder": "Открыть",
    "Show in folder": "Показать в папке",
    "Open": "Открыть",
    "Nothing was written": "Файл не создан",
    "This action uses only the first matching file.": "Это действие применится только к первому подходящему файлу.",
    "Other file types were skipped.": "Файлы других типов пропущены.",
    "of other types were skipped": "другого типа пропущено",
    "of": "из",
    "files": "файлов",
    "file": "файл",
    "pages": "страниц",
    "page": "страница",
    "smaller": "меньше",
    "larger": "больше",
    "same size": "тот же размер",
    "already well compressed": "уже хорошо сжат",
    "private copy": "копия без личных данных",
    "burned into pixels": "изменение записано в пиксели",
    "encrypted": "зашифровано",
    "Background added": "Фон добавлен",
    "Annotated": "Разметка добавлена",
    "Redacted": "Данные скрыты",
    "Metadata removed": "Метаданные удалены",
    "Password protected": "PDF защищён паролем",
    "Convert to": "Преобразование в",
    "Compressing…": "Сжатие…",
    "Converting to {name}…": "Преобразование в {name}…",
    "Combining {count} images…": "Объединение изображений: {count}…",
    "Merging…": "Объединение…",
    "Splitting…": "Разделение…",
    "Rotating…": "Поворот…",
    "Extracting images…": "Извлечение изображений…",
    "Working…": "Обработка…",
    "Cropping…": "Обрезка…",
    "Adding background…": "Добавление фона…",
    "Annotating…": "Добавление разметки…",
    "Redacting…": "Скрытие данных…",
    "Removing metadata…": "Удаление метаданных…",
    "Removing location…": "Удаление геоданных…",
    "Resizing…": "Изменение размера…",
    "Encrypting…": "Шифрование…",
    "Only matching files will be processed": "Будут обработаны только файлы подходящего типа",
    "MultiShift is running": "MultiShift запущен",
    "About MultiShift — originals are never modified": "MultiShift · исходные файлы не меняются",
}


def set_language(language: str) -> None:
    global _language
    _language = language if language in {"ru", "en"} else "ru"


def language() -> str:
    return _language


def tr(text: str) -> str:
    if not isinstance(text, str) or _language == "en":
        return text
    translated = RU.get(text)
    if translated is not None:
        return translated
    match = re.fullmatch(r"Show all (\d+) fields", text)
    if match:
        return f"Показать все поля: {match.group(1)}"
    match = re.fullmatch(r"(Compress|Resize) (\d+) files", text)
    if match:
        action = "Сжать" if match.group(1) == "Compress" else "Изменить размер"
        return f"{action} {match.group(2)} {file_word(int(match.group(2)))}"
    match = re.fullmatch(r"(\d+) files  ·  (.+)", text)
    if match:
        return f"{match.group(1)} {file_word(int(match.group(1)))}  ·  {match.group(2)}"
    match = re.fullmatch(r"(\d+) areas hidden", text)
    if match:
        n = int(match.group(1))
        noun = "область скрыта" if n % 10 == 1 and n % 100 != 11 else "области скрыто"
        return f"{n} {noun}"
    if text.startswith("Output  "):
        return f"Результат  {text[len('Output  '):]}"
    match = re.fullmatch(r"MultiShift ([\d.]+)  ·  originals are never modified", text)
    if match:
        return f"MultiShift {match.group(1)} · исходные файлы не меняются"
    match = re.fullmatch(r"Press (.+)", text)
    if match:
        return f"Нажмите {match.group(1)}"
    match = re.fullmatch(r"Tap (.+) again", text)
    if match:
        return f"Нажмите {match.group(1)} ещё раз"
    suffix = " — MultiShift"
    if text.endswith(suffix):
        return f"{tr(text[:-len(suffix)])}{suffix}"
    return text


def file_word(count: int) -> str:
    if _language != "ru":
        return "file" if count == 1 else "files"
    n = abs(count) % 100
    if 11 <= n <= 14:
        return "файлов"
    return {1: "файл", 2: "файла", 3: "файла", 4: "файла"}.get(n % 10, "файлов")


def page_word(count: int) -> str:
    if _language != "ru":
        return "page" if count == 1 else "pages"
    n = abs(count) % 100
    if 11 <= n <= 14:
        return "страниц"
    return {1: "страница", 2: "страницы", 3: "страницы", 4: "страницы"}.get(n % 10, "страниц")


_SOURCE_ROLE = 0x4D53


def apply_tree(root: Any) -> None:
    """Translate visible Qt text while retaining the original source string."""
    try:
        from PySide6.QtCore import QObject, Qt
        from PySide6.QtWidgets import (QAbstractButton, QComboBox, QGroupBox, QLabel,
                                       QLineEdit, QMenu, QTableWidget, QWidget)
    except ImportError:
        return

    objects = [root]
    if isinstance(root, QObject):
        objects.extend(root.findChildren(QObject))
    if hasattr(root, "topLevelWidgets"):
        for widget in root.topLevelWidgets():
            objects.append(widget)
            objects.extend(widget.findChildren(QObject))

    seen: set[int] = set()
    for obj in objects:
        if id(obj) in seen:
            continue
        seen.add(id(obj))

        def translate_property(getter, setter, key: str):
            try:
                original = obj.property(key)
                if original is None:
                    original = getter()
                    obj.setProperty(key, original)
                setter(tr(str(original)))
            except (AttributeError, RuntimeError, TypeError):
                pass

        if isinstance(obj, QWidget):
            translate_property(obj.windowTitle, obj.setWindowTitle, "_multishift_title")
            translate_property(obj.toolTip, obj.setToolTip, "_multishift_tooltip")
        if isinstance(obj, QLabel) or isinstance(obj, QAbstractButton):
            translate_property(obj.text, obj.setText, "_multishift_text")
        if isinstance(obj, QGroupBox):
            translate_property(obj.title, obj.setTitle, "_multishift_group_title")
        if isinstance(obj, QLineEdit):
            translate_property(obj.placeholderText, obj.setPlaceholderText, "_multishift_placeholder")
        if isinstance(obj, QComboBox):
            for i in range(obj.count()):
                original = obj.itemData(i, _SOURCE_ROLE)
                if original is None:
                    original = obj.itemText(i)
                    obj.setItemData(i, original, _SOURCE_ROLE)
                obj.setItemText(i, tr(str(original)))
        if isinstance(obj, QTableWidget):
            original = obj.property("_multishift_header_labels")
            if original is None:
                original = [obj.horizontalHeaderItem(i).text()
                            if obj.horizontalHeaderItem(i) is not None else ""
                            for i in range(obj.columnCount())]
                obj.setProperty("_multishift_header_labels", original)
            obj.setHorizontalHeaderLabels([tr(str(value)) for value in original])
        if isinstance(obj, QMenu):
            translate_property(obj.title, obj.setTitle, "_multishift_menu_title")
        if hasattr(obj, "text") and hasattr(obj, "setText") and obj.__class__.__name__ == "QAction":
            translate_property(obj.text, obj.setText, "_multishift_action_text")
