"""Signed Sparkle deltas, verified against exact immutable release bundles."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import tempfile
import xml.etree.ElementTree as ET

NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'


def local_file(directory: Path, name: str) -> Path:
    if not isinstance(name, str) or not name or Path(name).name != name:
        raise ValueError('Invalid release file name')
    path = directory / name
    if path.is_symlink() or not path.is_file():
        raise ValueError('Missing or unsafe release file: ' + name)
    return path


def tree_inventory(root: Path) -> dict:
    """File bytes, modes, symlink destinations and empty directories; ignore times/xattrs."""
    result = {}
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root).as_posix()
        mode = stat.S_IMODE(path.lstat().st_mode)
        if path.is_symlink(): result[relative] = ('symlink', os.readlink(path))
        elif path.is_dir(): result[relative] = ('directory', mode)
        elif path.is_file(): result[relative] = ('file', mode, hashlib.sha256(path.read_bytes()).hexdigest())
        else: raise ValueError('Unsupported bundle entry: ' + relative)
    return result


def require_deltas(manifest: dict, previous_build: int) -> None:
    if not any(d.get('from_build') == previous_build for d in manifest.get('deltas', [])):
        raise ValueError(f'Release must contain a verified delta from current build {previous_build}')


def require_client_check(manifest: dict, previous_build: int) -> None:
    require_deltas(manifest, previous_build)
    delta = next(d for d in manifest['deltas'] if d['from_build'] == previous_build)
    checks = [c for c in manifest.get('client_checks', []) if c.get('from_build') == previous_build
              and c.get('to_build') == manifest['build']]
    if len(checks) != 1: raise ValueError('Missing real Sparkle client acceptance check')
    check = checks[0]
    if (check.get('selected_delta') is not True or check.get('binary_delta_applied_and_validated') is not True
            or check.get('patch_sha256') != delta['sha256']
            or check.get('installed') is not False or check.get('archive') != delta['archive']
            or check.get('downloaded_bytes') != delta['bytes'] or check.get('expected_bytes') != delta['bytes']):
        raise ValueError('Sparkle client did not validate this exact delta')


def validate_refresh(previous: dict, manifest: dict) -> None:
    """A feed-only revision must never replace immutable artifacts or reduce existing routes."""
    ignored = {'deltas', 'client_checks'}
    if {k:v for k,v in previous.items() if k not in ignored} != {k:v for k,v in manifest.items() if k not in ignored}:
        raise ValueError('Delta refresh cannot change release artifacts or metadata')
    if not manifest.get('deltas'): raise ValueError('Delta refresh needs delta files')
    for delta in previous.get('deltas', []):
        if delta not in manifest['deltas']: raise ValueError('Delta refresh cannot remove or replace existing deltas')


def validate_deltas(directory: Path, manifest: dict, item: ET.Element, base: str, verify_signature) -> set[str]:
    deltas = manifest.get('deltas', [])
    if not isinstance(deltas, list): raise ValueError('Invalid delta manifest')
    enclosures = item.findall(f'{{{NS}}}deltas/enclosure')
    if len(enclosures) != len(deltas): raise ValueError('Feed and manifest deltas differ')
    names, versions = set(), set()
    for delta in deltas:
        version = delta.get('from_build')
        if type(version) is not int or not 0 < version < manifest['build'] or version in versions:
            raise ValueError('Invalid or duplicate delta base build')
        versions.add(version)
        if delta.get('to_build') != manifest['build']:
            raise ValueError('Delta target build mismatch')
        if type(delta.get('sparkle_executable_bytes')) is not int or delta['sparkle_executable_bytes'] <= 0:
            raise ValueError('Invalid Sparkle executable size')
        path = local_file(directory, delta['archive'])
        if path.name in names or not path.name.endswith('.delta'): raise ValueError('Invalid delta name')
        names.add(path.name)
        if type(delta['bytes']) is not int or not 0 < delta['bytes'] < manifest['bytes']:
            raise ValueError('Delta must be smaller than full archive')
        if path.stat().st_size != delta['bytes'] or hashlib.sha256(path.read_bytes()).hexdigest() != delta['sha256']:
            raise ValueError('Delta changed after signing')
        if any(not isinstance(delta.get(k), str) or not re.fullmatch(r'[a-f0-9]{64}', delta[k])
               for k in ('verified_tree_sha256', 'base_archive_sha256')):
            raise ValueError('Missing delta application verification')
        matches = [node for node in enclosures if node.get(f'{{{NS}}}deltaFrom') == str(version)]
        if len(matches) != 1: raise ValueError('Delta base missing or duplicated in feed')
        node = matches[0]
        expected = {'url': base + path.name, 'length': str(delta['bytes']),
                    'type': 'application/octet-stream', f'{{{NS}}}edSignature': delta['signature'],
                    f'{{{NS}}}deltaFromSparkleExecutableSize': str(delta['sparkle_executable_bytes'])}
        if any(node.get(key) != value for key, value in expected.items()):
            raise ValueError('Delta feed metadata mismatch')
        verify_signature(path, delta['signature'])
    return names


def add_delta_enclosures(item: ET.Element, deltas: list[dict], base: str) -> None:
    for old in item.findall(f'{{{NS}}}deltas'): item.remove(old)
    if deltas:
        parent = ET.SubElement(item, f'{{{NS}}}deltas')
        for delta in deltas:
            ET.SubElement(parent, 'enclosure', {
                'url': base + delta['archive'], 'length': str(delta['bytes']),
                'type': 'application/octet-stream', f'{{{NS}}}deltaFrom': str(delta['from_build']),
                f'{{{NS}}}edSignature': delta['signature'],
                f'{{{NS}}}deltaFromSparkleExecutableSize': str(delta['sparkle_executable_bytes']),
            })


def create_delta(previous: Path, target: Path, output: Path, sparkle: Path, key: bytes) -> dict:
    # Lazy imports avoid a cycle with build_release.feed().
    from build_release import sign
    before_manifest = json.loads((previous / 'latest.json').read_text())
    after_manifest = json.loads((target / 'latest.json').read_text())
    for folder, m in [(previous, before_manifest), (target, after_manifest)]:
        archive = local_file(folder, m['archive'])
        if hashlib.sha256(archive.read_bytes()).hexdigest() != m['sha256']:
            raise ValueError('Release archive hash mismatch')
    if before_manifest['updater_public_key'] != after_manifest['updater_public_key']:
        raise ValueError('Previous and target updater keys differ')
    if before_manifest['build'] >= after_manifest['build']:
        raise ValueError('Delta must increase build number')
    name = f"MultiShift-{before_manifest['build']}-{after_manifest['build']}-arm64.delta"
    patch = output / name
    if patch.exists(): raise ValueError('Refusing to overwrite delta')
    with tempfile.TemporaryDirectory(prefix='multishift-delta-') as temp:
        temp = Path(temp)
        for folder, m, label in [(previous, before_manifest, 'old'), (target, after_manifest, 'new')]:
            destination = temp / label
            destination.mkdir()
            subprocess.run(['ditto', '-x', '-k', str(folder / m['archive']), str(destination)], check=True)
            app = destination / 'MultiShift.app'
            info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
            if info['CFBundleVersion'] != str(m['build']) or info['SUPublicEDKey'] != m['updater_public_key']:
                raise ValueError('Bundle identity does not match manifest')
            if info['CFBundleIdentifier'] != 'com.multiswitcher.multishift': raise ValueError('Wrong bundle')
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        before, after = temp / 'old/MultiShift.app', temp / 'new/MultiShift.app'
        framework = before / 'Contents/Frameworks/Sparkle.framework/Versions/B'
        version = plistlib.loads((framework / 'Resources/Info.plist').read_bytes())['CFBundleShortVersionString']
        if tuple(map(int, version.split('.')[:2])) < (2, 7):
            raise ValueError('Delta format 4 requires Sparkle 2.7 or newer in previous app')
        subprocess.run([str(sparkle / 'bin/BinaryDelta'), 'create', '--version', '4', str(before), str(after), str(patch)], check=True)
        (temp / 'patched').mkdir()
        patched = temp / 'patched/MultiShift.app'
        subprocess.run([str(sparkle / 'bin/BinaryDelta'), 'apply', str(before), str(patched), str(patch)], check=True)
        expected = tree_inventory(after)
        if tree_inventory(patched) != expected: raise ValueError('Patched bundle differs from target')
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(patched)], check=True)
        subprocess.run([str(patched / 'Contents/MacOS/MultiShift'), '--selftest'], check=True)
        if not patch.stat().st_size < after_manifest['bytes']: raise ValueError('Delta is not smaller than full archive')
        signature = sign(sparkle / 'bin/sign_update', key, patch)
        sign(sparkle / 'bin/sign_update', key, patch, verify=True, signature=signature)
        return dict(from_version=before_manifest['version'], from_build=before_manifest['build'],
                    to_build=after_manifest['build'], archive=name, bytes=patch.stat().st_size,
                    sha256=hashlib.sha256(patch.read_bytes()).hexdigest(), signature=signature,
                    base_archive_sha256=before_manifest['sha256'],
                    verified_tree_sha256=hashlib.sha256(json.dumps(expected, sort_keys=True).encode()).hexdigest(),
                    sparkle_executable_bytes=(framework / 'Sparkle').stat().st_size)


def prepare_existing(target: Path, previous: list[Path], output: Path, seed: Path, sparkle: Path, base: str):
    from build_release import key_material, sign
    from publish_release import verify
    import shutil
    verify(target, seed, sparkle)
    for folder in previous: verify(folder, seed, sparkle)
    if output.exists(): raise ValueError('Output must not already exist')
    shutil.copytree(target, output)
    public, key = key_material(seed.read_bytes())
    manifest = json.loads((output / 'latest.json').read_text())
    if manifest.get('deltas'): raise ValueError('Target already has deltas; use an unmodified release')
    deltas = [create_delta(folder, target, output, sparkle, key) for folder in previous]
    manifest['deltas'] = deltas
    (output / 'latest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    feed = ET.parse(output / 'appcast.xml')
    add_delta_enclosures(feed.find('./channel/item'), deltas, base)
    feed.write(output / 'appcast.xml', encoding='utf-8', xml_declaration=True)
    sign(sparkle / 'bin/sign_update', key, output / 'appcast.xml')
    with (output / 'SHA256SUMS').open('a') as out:
        for d in deltas: out.write(d['sha256'] + '  ' + d['archive'] + '\n')
    verify(output, seed, sparkle)
    from check_delta_client import check
    manifest['client_checks'] = [check(folder, output, seed, sparkle,
        output.parent / (output.name + f"-client-{d['from_build']}.json"))
        for folder, d in zip(previous, deltas)]
    for d in deltas: require_client_check(manifest, d['from_build'])
    (output / 'latest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    verify(output, seed, sparkle)
    return manifest


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('target', type=Path)
    parser.add_argument('--previous-release', type=Path, action='append', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--seed', type=Path, default=Path.home() / 'Library/Application Support/MultiReleases/Signing/MultiShift.seed')
    parser.add_argument('--sparkle', type=Path, default=Path('/tmp/multishift-sparkle-2.10.0'))
    args = parser.parse_args()
    result = prepare_existing(args.target.resolve(), [p.resolve() for p in args.previous_release], args.output.resolve(), args.seed, args.sparkle, 'https://sokolovmo.ru/multishift/')
    print(json.dumps({'version': result['version'], 'build': result['build'], 'deltas': result['deltas']}, indent=2))
