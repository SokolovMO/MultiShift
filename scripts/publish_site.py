"""Atomically update a product page and media, preserving signed release bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import uuid

REMOTE = 'vyrex_nl_project'


def ssh_python(program):
    return subprocess.check_output(['ssh', REMOTE, 'python3', '-'], input=program, text=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', choices=['multishift', 'multiswitcher'])
    parser.add_argument('template', type=Path)
    parser.add_argument('--asset', action='append', type=Path, default=[])
    args = parser.parse_args()
    assets = {}
    for path in args.asset:
        if not path.is_file() or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*\.(mp4|png|jpg|webp|gif|vtt)', path.name):
            parser.error(f'Not a supported public media asset: {path}')
        if path.name in assets:
            parser.error(f'Duplicate asset: {path.name}')
        assets[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    snapshot = json.loads(ssh_python(
        "import json,hashlib;from pathlib import Path;"
        f"p=Path('/var/www/{args.app}/current').resolve();"
        "print(json.dumps({'path':str(p),'manifest':json.loads((p/'latest.json').read_text()),"
        "'page_sha256':hashlib.sha256((p/'index.html').read_bytes()).hexdigest()}))"))
    manifest = snapshot['manifest']
    page = args.template.read_text()
    for key, value in {'@VERSION@': manifest['version'], '@ARCHIVE@': manifest['archive'],
                       '@DMG@': manifest['installer'], '@SOURCE@': manifest['source'],
                       '@RELEASE_URL@': f'https://sokolovmo.ru/{args.app}'}.items():
        page = page.replace(key, value)
    if re.search(r'@[A-Z_]+@', page):
        raise SystemExit('Unresolved page template token')
    stage = f'/var/www/{args.app}/.site-assets-{uuid.uuid4().hex}'
    program = r'''
import fcntl, hashlib, json, os, shutil
from pathlib import Path
root = Path('/var/www') / APP
staged = Path(STAGE)
with (root / '.publish.lock').open('w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    old = (root / 'current').resolve()
    if str(old) != SNAPSHOT['path'] or hashlib.sha256((old/'index.html').read_bytes()).hexdigest() != SNAPSHOT['page_sha256']:
        raise SystemExit('The live page changed; retry without overwriting concurrent work')
    manifest = json.loads((old/'latest.json').read_text())
    if manifest != SNAPSHOT['manifest']:
        raise SystemExit('Release metadata changed; retry page publication')
    for name, digest in ASSETS.items():
        if hashlib.sha256((staged/name).read_bytes()).hexdigest() != digest:
            raise SystemExit('Staged media checksum mismatch: ' + name)
    identity_input = PAGE.encode() + json.dumps(ASSETS, sort_keys=True).encode()
    identity = 'site-' + str(manifest['build']) + '-' + hashlib.sha256(identity_input).hexdigest()[:16]
    target = root/'releases'/identity
    if not target.exists():
        target.mkdir(mode=0o755)
        for source in old.iterdir():
            if source.name not in {'index.html', *ASSETS} and source.is_file() and not source.is_symlink():
                os.link(source, target/source.name)
        for name in ASSETS:
            shutil.copyfile(staged/name, target/name)
            (target/name).chmod(0o644)
        (target/'index.html').write_text(PAGE)
        (target/'index.html').chmod(0o644)
    if (target/'index.html').read_text() != PAGE:
        raise SystemExit('Existing page identity mismatch')
    for name, digest in ASSETS.items():
        if hashlib.sha256((target/name).read_bytes()).hexdigest() != digest:
            raise SystemExit('Published media checksum mismatch: ' + name)
    # Unchanged files remain the same inode, including every signed ZIP, DMG and delta.
    protected = []
    for source in old.iterdir():
        if source.name not in {'index.html', *ASSETS} and source.is_file() and not source.is_symlink():
            if not os.path.samefile(source, target/source.name):
                raise SystemExit('An existing release file changed: ' + source.name)
            protected.append(source.name)
    for name in ['latest.json', 'appcast.xml']:
        if (target/name).read_bytes() != (old/name).read_bytes():
            raise SystemExit('Signed update metadata changed: ' + name)
    if old != target:
        for name, destination in [('previous', old), ('current', target)]:
            temporary = root/('.'+name+'-next')
            temporary.unlink(missing_ok=True)
            temporary.symlink_to(destination)
            temporary.replace(root/name)
    print(json.dumps({'published':str(target),'previous':str(old),'preserved_files':protected,'assets':ASSETS}))
'''
    program = ('APP=' + repr(args.app) + '\nSNAPSHOT=' + repr(snapshot) + '\nPAGE=' + repr(page)
               + '\nASSETS=' + repr(assets) + '\nSTAGE=' + repr(stage) + '\n' + program)
    try:
        if assets:
            subprocess.run(['ssh', REMOTE, 'mkdir', '-p', stage], check=True)
            subprocess.run(['scp', *[str(p.resolve()) for p in args.asset], REMOTE + ':' + stage + '/'], check=True)
        print(ssh_python(program).strip())
    finally:
        # Only remove this invocation's private staging directory.
        ssh_python('import shutil;shutil.rmtree(' + repr(stage) + ',ignore_errors=True)')
    print(f'https://sokolovmo.ru/{args.app}/')


if __name__ == '__main__':
    main()
