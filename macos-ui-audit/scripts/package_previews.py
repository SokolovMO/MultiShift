#!/usr/bin/env python3
"""Package the exact audited apps and verify extracted executables and signatures."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {'MultiShift': '/Applications/MultiShift.app',
           'MultiSwitcher': '/Applications/MultiSwitcher.app'}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    destination = ROOT / 'previews'
    destination.mkdir(exist_ok=True)
    records = []
    for name, source in SOURCES.items():
        source = Path(source)
        archive = destination / (name + '-preview.zip')
        if archive.exists():
            archive.unlink()
        subprocess.run(['/usr/bin/ditto', '--norsrc', '--noextattr', '-c', '-k', '--keepParent', str(source), str(archive)], check=True)
        with tempfile.TemporaryDirectory(prefix='multi-ui-extracted-') as folder:
            subprocess.run(['/usr/bin/ditto', '-x', '-k', str(archive), folder], check=True)
            app = Path(folder) / source.name
            verification = subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app)], capture_output=True, text=True)
            assert verification.returncode == 0, verification.stderr
            binary = source / 'Contents/MacOS' / name
            extracted_binary = app / 'Contents/MacOS' / name
            assert sha(binary) == sha(extracted_binary)
            info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
            record = {'app': name, 'sourceApp': str(source), 'archive': str(archive),
                      'archiveSHA256': sha(archive), 'binarySHA256': sha(binary),
                      'extractedBinaryIdentical': True, 'codesignDeepStrictPassed': True,
                      'signatureVerification': verification.stderr.strip(),
                      'bundleIdentifier': info.get('CFBundleIdentifier'),
                      'version': info.get('CFBundleShortVersionString'),
                      'build': info.get('CFBundleVersion'), 'buildID': info.get('MultiShiftBuildID'),
                      'minimumSystemVersion': info.get('LSMinimumSystemVersion'),
                      'distribution': 'local development preview; notarization not claimed'}
            if name == 'MultiShift':
                probe = subprocess.run([str(extracted_binary), '--selftest'], capture_output=True, text=True, timeout=60,
                                       env=os.environ | {'MULTI_AUDIT_DATA_ROOT': str(ROOT / 'runtime/extracted-selftest')})
                assert probe.returncode == 0, probe.stderr
                record['extractedNativeSelftest'] = probe.stdout.strip()
            records.append(record)
    (ROOT / 'builds.json').write_text(json.dumps(records, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps(records, indent=2, ensure_ascii=False))

if __name__ == '__main__':
    main()
