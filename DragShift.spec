# PyInstaller spec. ONEFILE=1 -> portable single exe; otherwise a folder for the installer.
import os
import runpy
import sys
sys.path.insert(0, os.path.abspath("."))
from PyInstaller.utils.hooks import collect_all
from dragshift import __version__

onefile = os.environ.get("ONEFILE") == "1"
engine_only = os.environ.get("MULTISHIFT_ENGINE_ONLY") == "1"
heif_datas, heif_bins, heif_hidden = collect_all("pillow_heif")
license_datas = runpy.run_path("scripts/collect_licenses.py")["collect_license_data"]()
HIDDEN = [] if engine_only else ["PySide6.QtNetwork"]
if sys.platform == "win32":
    HIDDEN += ["win32com.client"]
elif sys.platform == "darwin" and not engine_only:
    HIDDEN += ["AppKit", "Quartz", "objc"]

EXCLUDES = ["tkinter", "PySide6.QtWebEngineCore", "PySide6.QtWebEngineWidgets", "PySide6.QtQml",
            "PySide6.QtQuick", "PySide6.Qt3DCore", "PySide6.QtMultimedia", "PySide6.QtCharts",
            "PySide6.QtDataVisualization", "PySide6.QtPdf", "pandas", "yaml", "PySide6.QtSql", "PySide6.QtTest",
            "PySide6.QtOpenGL", "PySide6.QtSvgWidgets", "PySide6.QtDesigner", "matplotlib", "scipy"]
if engine_only:
    EXCLUDES += ["PySide6", "shiboken6", "AppKit", "Quartz", "objc"]

a = Analysis(
    ["engine_main.py" if engine_only else "run.py"],
    datas=(heif_datas + license_datas) if engine_only else [("dragshift/assets", "dragshift/assets")] + heif_datas + license_datas,
    binaries=heif_bins,
    hiddenimports=HIDDEN + heif_hidden,
    excludes=EXCLUDES,
)

DROP = ("Qt6Quick", "Qt6Qml", "Qt6Pdf", "Qt6WebEngine", "Qt63D", "Qt6Multimedia", "Qt6Charts",
        "Qt6VirtualKeyboard", "Qt6Designer", "Qt6ShaderTools", "Qt6Sql", "Qt6Test", "opengl32sw",
        "Qt6OpenGL", "Qt6DataVisualization", "Qt6Positioning", "Qt6Sensors", "Qt6SerialPort",
        "Qt6Bluetooth", "Qt6Nfc", "Qt6RemoteObjects", "Qt6Scxml", "Qt6SpatialAudio", "Qt6TextToSpeech",
        "Qt6WebChannel", "Qt6WebSockets", "Qt6Svg", "qtquick", "qml",
        "libgtk-3", "libgdk-3", "libqgtk3", "libatk-")
a.binaries = [b for b in a.binaries if not any(d.lower() in b[0].lower() for d in DROP)]
a.datas = [d for d in a.datas if "translations" not in d[0].replace("\\", "/")
           or d[0].replace("\\", "/").endswith("qtbase_ru.qm")]

pyz = PYZ(a.pure)
import sys
IS_MAC = sys.platform == "darwin"
common = dict(name="DragShift", console=False, upx=False)
IS_LINUX = sys.platform.startswith("linux")
if IS_MAC and engine_only:
    common.update(name="MultiShiftEngine", console=True)
elif IS_MAC:
    common.update(name="MultiShift", icon="dragshift/assets/multishift.icns")
elif IS_LINUX:
    common.update(name="dragshift")       # icon comes from the .desktop file / hicolor theme
else:
    common.update(icon="dragshift/assets/dragshift.ico", version="installer/version_info.txt")

if IS_MAC and engine_only:
    exe = EXE(pyz, a.scripts, [], exclude_binaries=True, argv_emulation=False, **common)
    coll = COLLECT(exe, a.binaries, a.datas, name="MultiShiftEngine", upx=False)
elif IS_MAC:
    exe = EXE(pyz, a.scripts, [], exclude_binaries=True, argv_emulation=False, **common)
    coll = COLLECT(exe, a.binaries, a.datas, name="MultiShift", upx=False)
    app = BUNDLE(
        coll,
        name="MultiShift.app",
        icon="dragshift/assets/multishift.icns",
        bundle_identifier="com.multiswitcher.multishift",
        info_plist={
            "CFBundleName": "MultiShift",
            "CFBundleDisplayName": "MultiShift",
            "CFBundleShortVersionString": __version__,
            "CFBundleVersion": __version__,
            "LSUIElement": True,                 # menu-bar app, no Dock icon
            "LSMinimumSystemVersion": "14.0",
            "NSHighResolutionCapable": True,
            "NSRequiresAquaSystemAppearance": False,
            # show up in Finder's "Open With" for any file, and accept drops on the app icon
            "CFBundleDocumentTypes": [{
                "CFBundleTypeName": "Any file",
                "CFBundleTypeRole": "Viewer",
                "LSHandlerRank": "Alternate",
                "LSItemContentTypes": ["public.item", "public.content", "public.data"],
            }],
        },
    )
elif IS_LINUX:
    exe = EXE(pyz, a.scripts, [], exclude_binaries=True, **common)
    coll = COLLECT(exe, a.binaries, a.datas, name="dragshift", upx=False)  # no strip: breaks OpenBLAS with Debian 12 binutils
elif onefile:
    exe = EXE(pyz, a.scripts, a.binaries, a.datas, [], **common)
else:
    exe = EXE(pyz, a.scripts, [], exclude_binaries=True, **common)
    coll = COLLECT(exe, a.binaries, a.datas, name="DragShift", upx=False)
