"""Regression checks for localization, theming, batch reporting, and safe undo."""
from pathlib import Path
import sys

import pytest

from dragshift import __version__, appearance, l10n, report
from dragshift.app import DragShiftApp
from dragshift.toasts import trash


def test_action_ids_do_not_change_with_language(tmp_path):
    image = tmp_path / "Photo.png"
    image.touch()
    previous = l10n.language()
    try:
        l10n.set_language("ru")
        russian = DragShiftApp.build_rings(object(), [str(image)])
        compress_ru = next(item for item in russian["Tools"] if item.key == "tool:Compress")

        l10n.set_language("en")
        english = DragShiftApp.build_rings(object(), [str(image)])
        compress_en = next(item for item in english["Tools"] if item.key == "tool:Compress")

        assert compress_ru.key == compress_en.key == "tool:Compress"
        assert compress_ru.label == "Сжать"
        assert compress_en.label == "Compress"
    finally:
        l10n.set_language(previous)


@pytest.mark.skipif(sys.platform == "darwin",
                    reason="the macOS app now uses native SwiftUI instead of the Qt windows")
def test_language_translation_can_be_switched_back():
    from PySide6.QtWidgets import QApplication, QLabel, QWidget

    app = QApplication.instance() or QApplication([])
    root = QWidget()
    label = QLabel("Settings", root)
    old = l10n.language()
    try:
        l10n.set_language("ru")
        l10n.apply_tree(root)
        assert label.text() == "Настройки"
        l10n.set_language("en")
        l10n.apply_tree(root)
        assert label.text() == "Settings"
    finally:
        l10n.set_language(old)
        root.close()
        app.processEvents()


def test_remaining_tool_sections_and_version_line_are_localized():
    previous = l10n.language()
    try:
        l10n.set_language("ru")
        assert l10n.tr("ASPECT RATIO") == "ПРОПОРЦИИ"
        assert l10n.tr("BACKGROUND") == "ФОН"
        assert l10n.tr("EXACT SIZE") == "ТОЧНЫЙ РАЗМЕР"
        assert l10n.tr("PRESETS — PERCENT OR LONGEST SIDE IN PX").startswith("БЫСТРЫЙ РАЗМЕР")
        assert l10n.tr("Crop Image") == "Обрезка изображения"
        assert l10n.tr("Press Shift ⇧") == "Нажмите Shift ⇧"
        assert l10n.tr("Tap Shift ⇧ again") == "Нажмите Shift ⇧ ещё раз"
        source = f"MultiShift {__version__}  ·  originals are never modified"
        assert l10n.tr(source) == (
            f"MultiShift {__version__} · исходные файлы не меняются"
        )
    finally:
        l10n.set_language(previous)



def test_appearance_has_distinct_light_and_dark_palettes():
    light = appearance.palette_for("light")
    dark = appearance.palette_for("dark")
    assert light.color(light.ColorRole.Window).lightness() > 200
    assert dark.color(dark.ColorRole.Window).lightness() < 80


def test_partial_batch_keeps_success_and_reports_failed_input(tmp_path):
    first = tmp_path / "first.png"
    broken = tmp_path / "broken.png"
    last = tmp_path / "last.png"
    out1, out2 = tmp_path / "first.jpg", tmp_path / "last.jpg"
    first.touch()
    broken.touch()
    last.touch()
    out1.write_bytes(b"first output")
    out2.write_bytes(b"last output")

    def convert_one(path: Path):
        if path == broken:
            raise ValueError("bad image")
        return [out1 if path == first else out2]

    previous = l10n.language()
    try:
        l10n.set_language("ru")
        batch = report.process_files([first, broken, last], convert_one)
        result = report.summarize("convert:JPG", [first, broken, last], batch)
        assert batch.succeeded_inputs == 2
        assert batch.outputs == [out1, out2]
        assert batch.failures == [("broken.png", "bad image")]
        assert result.title == "Готово с ошибками"
        assert "2 из 3" in result.detail and "broken.png" in result.detail
    finally:
        l10n.set_language(previous)


def test_undo_never_deletes_files_or_directories_when_trash_fails(monkeypatch, tmp_path):
    from PySide6.QtCore import QFile

    folder = tmp_path / "MultiShift"
    folder.mkdir()
    output = folder / "created.txt"
    output.write_text("keep on failed trash")
    monkeypatch.setattr(QFile, "moveToTrash", staticmethod(lambda _path: False))

    assert trash([output]) == 0
    assert output.read_text() == "keep on failed trash"
    assert folder.is_dir()
