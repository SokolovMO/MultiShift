# Third-party notices

MultiShift incorporates and bundles third-party software. The release build collects the license files shipped with its exact locked runtime dependencies under `MultiShift.app/Contents/Resources/ThirdPartyLicenses/`, together with a generated version and license inventory.

## DragShift origin

MultiShift is derived from [DragShift](https://github.com/llamaboi55/DragShift).
Copyright (c) 2026 DragShift contributors. Its original MIT permission and warranty notice
are preserved below and in the bundled component notices. MultiShift's native macOS shell
and later changes are maintained separately; this repository is not an official DragShift release.

## MIT-licensed components

Component copyright and permission notices are preserved in [licenses/third-party-components-MIT.txt](licenses/third-party-components-MIT.txt) and included in the application bundle.

## PyMuPDF and MuPDF

The application includes PyMuPDF for PDF processing. PyMuPDF and MuPDF are offered under GNU AGPL v3 or a separate commercial license. MultiShift's combined source is therefore distributed under GNU AGPL v3. The corresponding MultiShift source is available in this repository; each release must include its source revision and the AGPL license text. See the [official PyMuPDF licensing information](https://github.com/pymupdf/PyMuPDF#licensing) and [GNU AGPL v3](https://www.gnu.org/licenses/agpl-3.0.html).

## Qt for Python

The community PySide6 distribution follows Qt's LGPLv3/GPLv3 licensing. MultiShift uses the Qt modules required by its interface and packages their shared libraries. The bundle includes the license materials shipped with the exact PySide6/Qt wheels. See [Qt for Python licensing](https://doc.qt.io/qtforpython-6/), [Qt's LGPL guidance](https://doc.qt.io/qt-6/licensing.html), and the Qt sources at [code.qt.io](https://code.qt.io/).

## Other runtime packages

Pillow, pillow-heif, NumPy, python-docx, PyObjC, and their transitive runtime dependencies retain their own copyrights and licenses. The release bundle's generated inventory and collected license texts identify the exact package versions used for that build.

Do not redistribute a release after removing these notices or changing bundled library files in a way that prevents recipients from exercising rights granted by the applicable licenses. This notice is a package inventory, not legal advice.

## Additional conversion engines

The document/media engines and conversion-quality improvements include adapted MIT-licensed DragShift contributions from [PR #15](https://github.com/llamaboi55/DragShift/pull/15) (revision `5adf9ae41026671101f0abf8d118a4a850c7e5e2`) and [PR #6](https://github.com/llamaboi55/DragShift/pull/6) (revision `690cba9c1f96c6849c47ea7b294c60d26a5a4841`). The existing contributor copyright and MIT permission notice apply. These were adapted to the native shell and private staging rather than merged as upstream releases.

The bundled imageio-ffmpeg wheel supplies FFmpeg; the dependency inventory includes its distributed license materials. Other added runtime dependencies include Markdown, openpyxl, python-pptx, striprtf and pdf2docx (with OpenCV). Release source and dependency license collection remain part of the build. LibreOffice is an optional external application and is not bundled.
