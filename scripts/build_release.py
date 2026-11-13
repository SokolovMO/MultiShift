"""Build an independent, Ed25519-signed static distribution. No Apple account/API."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tarfile
import tempfile
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET
from build_dmg import create as create_dmg

ROOT = Path(__file__).resolve().parents[1]
NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', NS)


def release_url(value):
    url = urlsplit(value)
    if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment:
        raise ValueError('release URL must be an HTTPS directory without credentials, query or fragment')
    return value.rstrip('/') + '/'


def key_material(seed):
    if len(seed) != 32:
        raise ValueError('expected a 32-byte Ed25519 seed')
    der = bytes.fromhex('302e020100300506032b657004220420') + seed
    public = subprocess.run(['openssl', 'pkey', '-inform', 'DER', '-pubout', '-outform', 'DER'],
                            input=der, capture_output=True, check=True).stdout[-32:]
    return base64.b64encode(public).decode(), base64.b64encode(seed)


def sign(binary, key, path, verify=False, signature=None):
    args = [str(binary), '--ed-key-file', '-']
    if verify:
        args.append('--verify')
    elif path.suffix != '.xml':
        args.append('-p')
    args.append(str(path))
    if signature:
        args.append(signature)
    result = subprocess.run(args, input=key, capture_output=True, check=True)
    return result.stdout.decode().strip()


def feed(version, build, base, archive, signature, size, source, deltas=()):
    rss = ET.Element('rss', {'version': '2.0'})
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'MultiShift'
    ET.SubElement(channel, 'link').text = base
    ET.SubElement(channel, 'description').text = 'MultiShift updates'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'MultiShift {version}'
    for name, value in [('version', build), ('shortVersionString', version),
                        ('minimumSystemVersion', '14.0.0'), ('hardwareRequirements', 'arm64')]:
        ET.SubElement(item, f'{{{NS}}}{name}').text = value
    ET.SubElement(item, 'link').text = base
    for language, heading, detail, label in [
        ('ru', 'Обновление MultiShift',
         'Исправлена кнопка «Открыть» в результате операции, истории и уведомлениях. '
         'Если файл перемещён, удалён или macOS не может его открыть, приложение теперь показывает понятное сообщение. '
         'Доступна установка через Homebrew. Настройки и история сохраняются. '
         'Установка начнётся после подтверждения и завершения активных операций.',
         'Исходный код выпуска'),
        ('en', 'MultiShift update',
         'Fixed Open in operation results, history and notifications. '
         'When an output has moved, was deleted or cannot be opened by macOS, the app now explains the problem. '
         'Homebrew installation is available. Settings and history are preserved. '
         'Installation requires confirmation and waits for active operations to finish.',
         'Release source code')]:
        ET.SubElement(item, 'description', {
            '{http://www.w3.org/XML/1998/namespace}lang': language
        }).text = ('<style>body{font:13px -apple-system,BlinkMacSystemFont,sans-serif;line-height:1.5;color:#1a1a1a} '
                  'h3{font-size:16px;margin:0 0 12px} a{color:inherit;text-underline-offset:2px} '
                  '@media(prefers-color-scheme:dark){body{color:#f0f0f0}}</style>'
                  f'<h3>{heading}</h3><p>{detail}</p><p><a href="{base}{source}">{label}</a></p>')
    ET.SubElement(item, 'enclosure', {'url': base + archive, 'length': str(size),
                                    'type': 'application/octet-stream', f'{{{NS}}}edSignature': signature})
    from release_deltas import add_delta_enclosures
    add_delta_enclosures(item, list(deltas), base)
    return ET.tostring(rss, encoding='utf-8', xml_declaration=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--previous-release', type=Path, action='append', required=True,
                        help='Verified previous release directory; required for delta generation')
    parser.add_argument('--url', default='https://sokolovmo.ru/multishift/')
    parser.add_argument('--seed', type=Path, default=Path.home() / 'Library/Application Support/MultiReleases/Signing/MultiShift.seed')
    parser.add_argument('--sparkle', type=Path, default=Path('/tmp/multishift-sparkle-2.10.0'))
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/release')
    args = parser.parse_args()
    base = release_url(args.url)
    from publish_release import verify
    for previous in args.previous_release:
        verify(previous, args.seed, args.sparkle)
    public, key = key_material(args.seed.read_bytes())
    binary = args.sparkle / 'bin/sign_update'
    if not binary.is_file():
        raise SystemExit('Run bash scripts/prepare_sparkle.sh first')
    if not (ROOT / '.build/release-tools/bin/dmgbuild').is_file():
        raise SystemExit('Run bash scripts/prepare_dmg.sh first')
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        raise SystemExit('Output must be empty; each release is built into a separate directory')
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='multishift-release-') as temporary:
        env = dict(os.environ, MULTISHIFT_ENABLE_UPDATES='1', MULTISHIFT_RELEASE_URL=base,
                   MULTISHIFT_SPARKLE_PUBLIC_KEY=public,
                   MULTISHIFT_SPARKLE_FRAMEWORK=str(args.sparkle / 'Sparkle.framework'),
                   MULTISHIFT_OUTPUT_DIR=temporary)
        subprocess.run(['bash', 'scripts/build_macos.sh'], cwd=ROOT, env=env, check=True)
        app = Path(temporary) / 'MultiShift.app'
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
        if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'[1-9]\d*', build):
            raise ValueError('invalid version/build')
        # Only arm64 has been built and accepted. Never advertise a universal ZIP.
        if subprocess.check_output(['uname', '-m'], text=True).strip() != 'arm64':
            raise ValueError('this release target requires Apple Silicon')
        archive = output / f'MultiShift-{version}-{build}-arm64.zip'
        subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
        unpacked = Path(temporary) / 'verified'
        subprocess.run(['ditto', '-x', '-k', str(archive), str(unpacked)], check=True)
        extracted = unpacked / 'MultiShift.app'
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(extracted)], check=True)
        subprocess.run([str(extracted / 'Contents/MacOS/MultiShift'), '--selftest'], check=True)
        signature = sign(binary, key, archive)
        sign(binary, key, archive, verify=True, signature=signature)
        dmg = output / f'MultiShift-{version}-{build}-arm64.dmg'
        create_dmg(extracted, dmg)
        dmg_signature = sign(binary, key, dmg)
        sign(binary, key, dmg, verify=True, signature=dmg_signature)
        source = output / f'MultiShift-{version}-{build}-source.tar.gz'
        # Archive actual inputs (including local edits), not an older HEAD snapshot.
        names = ['dragshift', 'macos', 'scripts', 'installer', 'licenses', 'tests', '.github',
                 'requirements.txt', 'requirements-macos.lock', 'engine_main.py', 'DragShift.spec',
                 'AGENTS.md', 'CHANGELOG.md', 'CONTRIBUTING.md', 'SECURITY.md', 'CODE_OF_CONDUCT.md', 'LICENSE', 'THIRD-PARTY-NOTICES.md', 'requirements-release.lock', 'README.md', 'install-mac.sh', 'release-site', 'docs/assets', 'docs/screenshots', 'docs/README.ru.md', 'docs/ARCHITECTURE.md', 'docs/PRIVACY.md', 'docs/DISTRIBUTION.md', 'docs/NATIVE-FEATURES-2026-11-12.md']
        def source_filter(entry):
            if any(part in {'.build', '__pycache__', '.DS_Store', '.pytest_cache'} for part in Path(entry.name).parts):
                return None
            return entry
        with tarfile.open(source, 'w:gz') as bundle:
            for name in names:
                bundle.add(ROOT / name, arcname='MultiShift/' + name, filter=source_filter)
        manifest = dict(version=version, build=int(build), architecture='arm64', minimum_macos='14.0',
                        archive=archive.name, bytes=archive.stat().st_size,
                        sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
                        updater_public_key=public, source=source.name, notarized=False,
                        installer=dmg.name, installer_bytes=dmg.stat().st_size,
                        installer_sha256=hashlib.sha256(dmg.read_bytes()).hexdigest(),
                        installer_signature=dmg_signature)
        (output / 'latest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        from release_deltas import create_delta, require_deltas
        manifest['deltas'] = [create_delta(previous.resolve(), output, output, args.sparkle, key)
                              for previous in args.previous_release]
        require_deltas(manifest, max(json.loads((p / 'latest.json').read_text())['build'] for p in args.previous_release))
        (output / 'latest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        appcast = output / 'appcast.xml'
        appcast.write_bytes(feed(version, build, base, archive.name, signature, archive.stat().st_size, source.name, manifest['deltas']))
        sign(binary, key, appcast)
        sign(binary, key, appcast, verify=True)
        installer = (ROOT / 'install-mac.sh').read_text().replace('@RELEASE_URL@', base.rstrip('/')).replace('@PUBLIC_KEY@', public)
        (output / 'install.sh').write_text(installer)
        page = (ROOT / 'release-site/index.html').read_text()
        for token, value in {'@ARCHIVE@': archive.name, '@DMG@': dmg.name, '@VERSION@': version,
                             '@SOURCE@': source.name, '@RELEASE_URL@': base.rstrip('/')}.items():
            page = page.replace(token, value)
        (output / 'index.html').write_text(page)
        # Keep the product demo available after a future application release.
        for name in ('multishift-demo.mp4', 'multishift-demo-poster.png'):
            asset = ROOT / 'release-site' / name
            if asset.is_file():
                shutil.copyfile(asset, output / name)
        for name in ['LICENSE', 'THIRD-PARTY-NOTICES.md']:
            shutil.copyfile(ROOT / name, output / name)
        (output / 'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in [archive, dmg, source] + [output / d["archive"] for d in manifest["deltas"]]))
    from check_delta_client import check
    from release_deltas import require_client_check
    # A real previous-version Sparkle client must download only the delta before publication.
    with tempfile.TemporaryDirectory(prefix='multishift-client-report-') as checks:
        manifest['client_checks'] = [check(previous.resolve(), output, args.seed, args.sparkle,
                                          Path(checks) / f"client-{index}.json")
                                     for index, previous in enumerate(args.previous_release)]
    for previous in args.previous_release:
        require_client_check(manifest, json.loads((previous / 'latest.json').read_text())['build'])
    (output / 'latest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    verify(output, args.seed, args.sparkle)
    print(f'Verified static release with Sparkle delta download: {output}')


if __name__ == '__main__':
    main()
