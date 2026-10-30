# Third-party notices

MultiShift incorporates and bundles third-party software. The release build collects the license files shipped with its exact locked runtime dependencies under `MultiShift.app/Contents/Resources/ThirdPartyLicenses/`, together with a generated version and license inventory.

## MIT-licensed components

Component copyright and permission notices are preserved in [licenses/third-party-components-MIT.txt](licenses/third-party-components-MIT.txt) and included in the application bundle.

## PyMuPDF and MuPDF

The application includes PyMuPDF for PDF processing. PyMuPDF and MuPDF are offered under GNU AGPL v3 or a separate commercial license. MultiShift's combined source is therefore distributed under GNU AGPL v3. The corresponding MultiShift source is available in this repository; each release must include its source revision and the AGPL license text. See the [official PyMuPDF licensing information](https://github.com/pymupdf/PyMuPDF#licensing) and [GNU AGPL v3](https://www.gnu.org/licenses/agpl-3.0.html).

## Qt for Python

The community PySide6 distribution follows Qt's LGPLv3/GPLv3 licensing. MultiShift uses the Qt modules required by its interface and packages their shared libraries. The bundle includes the license materials shipped with the exact PySide6/Qt wheels. See [Qt for Python licensing](https://doc.qt.io/qtforpython-6/), [Qt's LGPL guidance](https://doc.qt.io/qt-6/licensing.html), and the Qt sources at [code.qt.io](https://code.qt.io/).

## Other runtime packages

Pillow, pillow-heif, NumPy, python-docx, PyObjC, and their transitive runtime dependencies retain their own copyrights and licenses. The release bundle's generated inventory and collected license texts identify the exact package versions used for that build.

Do not redistribute a release after removing these notices or changing bundled library files in a way that prevents recipients from exercising rights granted by the applicable licenses. This notice is a package inventory, not legal advice.
