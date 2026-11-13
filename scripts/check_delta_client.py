"""Real Sparkle selects the delta; download its exact URL and verify/apply it without an installer."""
from __future__ import annotations
import argparse
import contextlib
import functools
import http.server
import json
import os
import plistlib
import shutil
import uuid
from pathlib import Path
import subprocess
import tempfile
import threading
import xml.etree.ElementTree as ET


def check(previous: Path, release: Path, seed: Path, sparkle: Path, report: Path, public_feed: str | None = None) -> dict:
    from build_release import key_material, sign, NS
    from publish_release import verify
    old = verify(previous, seed, sparkle)
    new = verify(release, seed, sparkle)
    matches = [d for d in new.get('deltas', []) if d['from_build'] == old['build']]
    if len(matches) != 1: raise ValueError('No unique delta for previous build')
    delta = matches[0]
    with tempfile.TemporaryDirectory(prefix='multishift-sparkle-client-') as temp:
        temp = Path(temp)
        unpacked = temp / 'host'; unpacked.mkdir()
        subprocess.run(['ditto', '-x', '-k', str(previous / old['archive']), str(unpacked)], check=True)
        exact_host = unpacked / 'MultiShift.app'
        # Separate the selector namespace from a possibly pending real user update.
        # Only CFBundleIdentifier changes; production patch application uses exact_host.
        host = temp / 'selector/MultiShift.app'
        host.parent.mkdir()
        subprocess.run(['ditto', str(exact_host), str(host)], check=True)
        info_path = host / 'Contents/Info.plist'
        info = plistlib.loads(info_path.read_bytes())
        info['CFBundleIdentifier'] = 'com.multishift.delta-probe.' + uuid.uuid4().hex
        info_path.write_bytes(plistlib.dumps(info))
        subprocess.run(['codesign', '--force', '--sign', '-', str(host)], check=True)
        binary = temp / 'delta-probe'
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-F', str(host / 'Contents/Frameworks'),
                        '-framework', 'Sparkle', '-Wl,-rpath,' + str(host / 'Contents/Frameworks'),
                        str(Path(__file__).with_suffix('.m')), '-o', str(binary)], check=True,
                       env={**os.environ, 'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer',
                            'CLANG_MODULE_CACHE_PATH': str(temp / 'module-cache')})
        subprocess.run(['codesign', '--force', '--sign', '-', str(binary)], check=True)
        web = temp / 'web'; web.mkdir()
        # No full ZIP is served. The test must fail instead of succeeding via fallback.
        shutil.copyfile(release / delta['archive'], web / delta['archive'])
        paths = []
        class Handler(http.server.SimpleHTTPRequestHandler):
            def do_GET(self):
                paths.append(self.path)
                super().do_GET()
            def log_message(self, *args): pass
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(web)))
        address = f'http://127.0.0.1:{server.server_port}/'
        feed = ET.parse(release / 'appcast.xml')
        for node in feed.findall('.//enclosure'):
            node.set('url', address + node.get('url').rsplit('/', 1)[-1])
        feed.write(web / 'appcast.xml', encoding='utf-8', xml_declaration=True)
        _, key = key_material(seed.read_bytes())
        sign(sparkle / 'bin/sign_update', key, web / 'appcast.xml')
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        try:
            # CFPreferences/cache isolation; the real installed app and its files are never targets.
            profile = temp / 'profile'; (profile / 'Library/Preferences').mkdir(parents=True)
            env = {**os.environ, 'CFFIXED_USER_HOME': str(profile),
                   'TMPDIR': str(temp)}
            subprocess.run([str(binary), str(host), public_feed or address + 'appcast.xml', delta['archive'], str(temp / 'probe.json')],
                           check=True, timeout=100, env=env)
            result = json.loads((temp / 'probe.json').read_text())
            if result['downloaded_bytes'] != delta['bytes'] or not result['selected_delta']:
                raise ValueError('Sparkle did not exclusively download the delta')
            if not public_feed and not any(p.split('?', 1)[0] == '/' + delta['archive'] for p in paths):
                raise ValueError('Server did not observe a delta request')
            if any(p.split('?', 1)[0].endswith('.zip') for p in paths):
                raise ValueError('Client attempted full archive fallback')
            from release_deltas import tree_inventory
            downloaded = temp / 'probe.json.delta'
            import hashlib
            if hashlib.sha256(downloaded.read_bytes()).hexdigest() != delta['sha256']:
                raise ValueError('Selected URL returned different patch bytes')
            sign(sparkle / 'bin/sign_update', key, downloaded, verify=True, signature=delta['signature'])
            (temp / 'patched').mkdir()
            patched = temp / 'patched/MultiShift.app'
            subprocess.run([str(sparkle / 'bin/BinaryDelta'), 'apply', str(exact_host), str(patched), str(downloaded)], check=True)
            inventory = tree_inventory(patched)
            inventory_hash = hashlib.sha256(json.dumps(inventory, sort_keys=True).encode()).hexdigest()
            if inventory_hash != delta['verified_tree_sha256']: raise ValueError('Downloaded patch does not restore target')
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(patched)], check=True)
            subprocess.run([str(patched / 'Contents/MacOS/MultiShift'), '--selftest'], check=True)
            result.update(binary_delta_applied_and_validated=True, patch_sha256=delta['sha256'],
                          from_build=old['build'], to_build=new['build'], full_archive_bytes=new['bytes'],
                          observed_requests=paths, scope='namespaced selector copy; patch applied to exact unmodified release',
                          feed_url=public_feed or address + 'appcast.xml',
                          selector_identity_isolated=True)
            report.parent.mkdir(parents=True, exist_ok=True)
            report.write_text(json.dumps(result, indent=2) + '\n')
            return result
        finally:
            server.shutdown(); server.server_close(); thread.join()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('previous', type=Path)
    parser.add_argument('release', type=Path)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--public-feed', help='Verify the published feed and download its selected delta URL')
    parser.add_argument('--seed', type=Path, default=Path.home() / 'Library/Application Support/MultiReleases/Signing/MultiShift.seed')
    parser.add_argument('--sparkle', type=Path, default=Path('/tmp/multishift-sparkle-2.10.0'))
    args = parser.parse_args()
    print(json.dumps(check(args.previous.resolve(), args.release.resolve(), args.seed, args.sparkle, args.report.resolve(), args.public_feed), indent=2))
