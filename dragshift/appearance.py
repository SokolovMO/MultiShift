"""System, light and dark appearance selection for the Qt interface."""
from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtGui import QColor, QGuiApplication, QPalette

_preference = "system"


def set_preference(value: str) -> None:
    global _preference
    _preference = value if value in {"system", "light", "dark"} else "system"


def preference() -> str:
    return _preference


def system_scheme(app=None) -> str:
    app = app or QGuiApplication.instance()
    if app is None:
        return "dark"
    try:
        scheme = app.styleHints().colorScheme()
        if scheme == Qt.ColorScheme.Light:
            return "light"
        if scheme == Qt.ColorScheme.Dark:
            return "dark"
    except (AttributeError, RuntimeError):
        pass
    try:
        return "light" if app.palette().color(QPalette.ColorRole.Window).lightness() > 128 else "dark"
    except (AttributeError, RuntimeError):
        return "dark"


def scheme(app=None) -> str:
    return system_scheme(app) if _preference == "system" else _preference


def is_light(app=None) -> bool:
    return scheme(app) == "light"


def palette_for(mode: str) -> QPalette:
    light = mode == "light"
    p = QPalette()
    roles = {
        QPalette.ColorRole.Window: QColor("#f2f2f2" if light else "#171719"),
        QPalette.ColorRole.WindowText: QColor("#1c1c1e" if light else "#f5f5f7"),
        QPalette.ColorRole.Base: QColor("#ffffff" if light else "#222225"),
        QPalette.ColorRole.AlternateBase: QColor("#e8e8ea" if light else "#29292d"),
        QPalette.ColorRole.Text: QColor("#1c1c1e" if light else "#f5f5f7"),
        QPalette.ColorRole.Button: QColor("#ffffff" if light else "#2a2a2e"),
        QPalette.ColorRole.ButtonText: QColor("#1c1c1e" if light else "#f5f5f7"),
        QPalette.ColorRole.Highlight: QColor("#1c1c1e" if light else "#f5f5f7"),
        QPalette.ColorRole.HighlightedText: QColor("#ffffff" if light else "#1c1c1e"),
        QPalette.ColorRole.ToolTipBase: QColor("#ffffff" if light else "#29292d"),
        QPalette.ColorRole.ToolTipText: QColor("#1c1c1e" if light else "#f5f5f7"),
        QPalette.ColorRole.PlaceholderText: QColor("#77777c" if light else "#a8a8ad"),
    }
    for role, color in roles.items():
        p.setColor(role, color)
    return p


def apply(app) -> None:
    """Apply semantic colors to the app and refresh already-open windows."""
    from . import glass

    light = is_light(app)
    app.setPalette(palette_for("light" if light else "dark"))
    app.setStyleSheet(glass.qss(light))
    for widget in app.topLevelWidgets():
        if widget.objectName() == "glassRoot":
            widget.setStyleSheet(glass.qss(light))
        refresh = getattr(widget, "refresh_theme", None)
        if callable(refresh):
            refresh()
        widget.update()
