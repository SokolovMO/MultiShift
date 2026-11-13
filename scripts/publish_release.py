"""Publish a verified static MultiShift release to Vyrex. No proxy restart."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import uuid
import xml.etree.ElementTree as ET
from build_release import NS, key_material, sign
from release_deltas import validate_deltas, require_client_check, validate_refresh

REMOTE = 'vyrex_nl_project'
BASE = '/var/www/multishift'
URL = 'https://sokolovmo.ru/multishift/'


def verify(directory, seed, sparkle):
    manifest = json.loads((directory / 'latest.json').read_text())
    public, key = key_material(seed.read_bytes())
    if manifest['updater_public_key'] != public:
        raise ValueError('wrong signing key')
    archive = directory / manifest['archive']
    if archive.name != manifest['archive'] or not archive.name.endswith('-arm64.zip'):
        raise ValueError('invalid archive name')
    if archive.stat().st_size != manifest['bytes'] or hashlib.sha256(archive.read_bytes()).hexdigest() != manifest['sha256']:
        raise ValueError('archive changed after signing')
    sign(sparkle / 'bin/sign_update', key, directory / 'appcast.xml', verify=True)
    item = ET.parse(directory / 'appcast.xml').find('./channel/item')
    enclosure = item.find('enclosure')
    if enclosure.get('url') != URL + archive.name or item.find(f'{{{NS}}}version').text != str(manifest['build']):
        raise ValueError('feed does not describe this release or server')
    sign(sparkle / 'bin/sign_update', key, archive, verify=True, signature=enclosure.get(f'{{{NS}}}edSignature'))
    for name in ['index.html', 'install.sh', 'LICENSE', 'THIRD-PARTY-NOTICES.md', 'SHA256SUMS', manifest['source']]:
        if Path(name).name != name or not (directory / name).is_file():
            raise ValueError('required distribution file missing')
    allowed = {'index.html', 'install.sh', 'LICENSE', 'THIRD-PARTY-NOTICES.md',
               'SHA256SUMS', 'latest.json', 'appcast.xml', manifest['source'], manifest['archive']}
    if installer := manifest.get('installer'):
        if Path(installer).name != installer or not installer.endswith('-arm64.dmg'):
            raise ValueError('invalid installer name')
        dmg = directory / installer
        if dmg.stat().st_size != manifest['installer_bytes'] or hashlib.sha256(dmg.read_bytes()).hexdigest() != manifest['installer_sha256']:
            raise ValueError('installer changed after signing')
        sign(sparkle / 'bin/sign_update', key, dmg, verify=True, signature=manifest['installer_signature'])
        allowed.add(installer)
    allowed |= validate_deltas(directory, manifest, item, URL,
                               lambda path, signature: sign(sparkle / 'bin/sign_update', key, path, verify=True, signature=signature))
    if any(p.name not in allowed or p.is_symlink() or not p.is_file() for p in directory.iterdir()):
        raise ValueError('unexpected distribution file; refuse to upload extra files')
    checked_names = set()
    for line in (directory / 'SHA256SUMS').read_text().splitlines():
        digest, name = line.split('  ', 1)
        if name in checked_names: raise ValueError('Duplicate checksum entry')
        checked_names.add(name)
        if Path(name).name != name or hashlib.sha256((directory / name).read_bytes()).hexdigest() != digest:
            raise ValueError('checksum mismatch')
    required = {manifest['archive'], manifest['source']} | {d['archive'] for d in manifest.get('deltas', [])}
    if manifest.get('installer'): required.add(manifest['installer'])
    if not required <= checked_names: raise ValueError('Missing required checksums')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--refresh-deltas', action='store_true', help='Publish only added delta metadata for the SAME immutable release')
    parser.add_argument('--seed', type=Path, default=Path.home() / 'Library/Application Support/MultiReleases/Signing/MultiShift.seed')
    parser.add_argument('--sparkle', type=Path, default=Path('/tmp/multishift-sparkle-2.10.0'))
    args = parser.parse_args()
    directory = args.directory.resolve()
    manifest = verify(directory, args.seed, args.sparkle)
    snapshot_program = "import json;from pathlib import Path;p=Path('/var/www/multishift/current');print(json.dumps({'path':str(p.resolve()),'manifest':json.loads((p/'latest.json').read_text())}))"
    snapshot = json.loads(subprocess.run(['ssh', REMOTE, 'python3', '-'], input=snapshot_program, text=True, capture_output=True, check=True).stdout)
    previous = snapshot['manifest']
    if args.refresh_deltas:
        validate_refresh(previous, manifest)
        for delta in manifest['deltas']: require_client_check(manifest, delta['from_build'])
    else:
        if manifest['build'] <= previous['build']: raise ValueError('Build number must increase')
        require_client_check(manifest, previous['build'])
    identity = f"build-{int(manifest['build'])}-{manifest['sha256'][:16]}"
    if args.refresh_deltas:
        identity += '-deltas-' + hashlib.sha256((directory / 'appcast.xml').read_bytes()).hexdigest()[:12]
    incoming = BASE + '/incoming-' + uuid.uuid4().hex
    subprocess.run(['ssh', REMOTE, 'mkdir', '-p', incoming], check=True)
    subprocess.run(['rsync', '-rt', '--link-dest=' + snapshot['path'], str(directory) + '/', REMOTE + ':' + incoming + '/'], check=True)
    # Remote program receives no keys. All paths are generated, not arbitrary shell input.
    program = r'''
import fcntl, hashlib, json, os
from pathlib import Path
root = Path('/var/www/multishift')
with (root / '.publish.lock').open('w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    incoming = Path(INCOMING)
    manifest = json.loads((incoming / 'latest.json').read_text())
    for line in (incoming / 'SHA256SUMS').read_text().splitlines():
        digest, name = line.split('  ', 1)
        if Path(name).name != name or hashlib.sha256((incoming / name).read_bytes()).hexdigest() != digest:
            raise SystemExit('Remote checksum mismatch')
    incoming.chmod(0o755)
    for entry in incoming.iterdir():
        entry.chmod(0o644)
    releases = root / 'releases'
    releases.mkdir(exist_ok=True)
    target = releases / IDENTITY
    if target.exists():
        raise SystemExit('Release already exists; do not overwrite immutable builds')
    current = root / 'current'
    old = current.resolve() if current.is_symlink() else None
    if str(old) != EXPECTED_CURRENT:
        raise SystemExit('Current release changed during upload; retry against the new base')
    if old:
        previous = json.loads((old / 'latest.json').read_text())
        if REFRESH_DELTAS:
            ignored = {'deltas', 'client_checks'}
            if {k:v for k,v in previous.items() if k not in ignored} != {k:v for k,v in manifest.items() if k not in ignored}:
                raise SystemExit('Delta refresh cannot replace immutable artifacts')
            old_checksums = dict(line.split('  ',1)[::-1] for line in (old / 'SHA256SUMS').read_text().splitlines())
            new_checksums = dict(line.split('  ',1)[::-1] for line in (incoming / 'SHA256SUMS').read_text().splitlines())
            if any(new_checksums.get(name) != digest for name,digest in old_checksums.items()):
                raise SystemExit('Delta refresh changed an immutable checksum')
        elif int(previous['build']) >= int(manifest['build']):
            raise SystemExit('Build number must increase')
        if not REFRESH_DELTAS and not any(d.get('from_build') == previous['build'] for d in manifest.get('deltas', [])):
            raise SystemExit('Missing delta from previous published build')
        # Old ZIP/source links remain available after the directory switch.
        for pattern in ('MultiShift-*.zip', 'MultiShift-*.dmg', 'MultiShift-*-source.tar.gz', 'MultiShift-*.delta'):
            for archive in old.glob(pattern):
                destination = incoming / archive.name
                if not destination.exists():
                    os.link(archive, destination)
    if manifest.get('installer') and not (incoming / 'installer.dmg').exists():
        os.link(incoming / manifest['installer'], incoming / 'installer.dmg')
    incoming.rename(target)
    if old:
        temporary = root / '.previous-next'
        temporary.unlink(missing_ok=True)
        temporary.symlink_to(old)
        temporary.replace(root / 'previous')
    temporary = root / '.current-next'
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(target)
    temporary.replace(current)
    print('Published', target.name)
'''
    program = 'EXPECTED_CURRENT = ' + repr(snapshot['path']) + '\nREFRESH_DELTAS = ' + repr(args.refresh_deltas) + '\n' + 'INCOMING = ' + repr(incoming) + '\nIDENTITY = ' + repr(identity) + '\n' + program
    subprocess.run(['ssh', REMOTE, 'python3', '-'], input=program, text=True, check=True)
    print(URL)


if __name__ == '__main__':
    main()
