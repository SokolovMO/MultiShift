"""Atomically update only a product page, preserving signed release bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

REMOTE='vyrex_nl_project'
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('app',choices=['multishift','multiswitcher'])
parser.add_argument('template',type=Path)
args=parser.parse_args()
manifest=json.loads(subprocess.check_output(['ssh',REMOTE,'cat',f'/var/www/{args.app}/current/latest.json'],text=True))
page=args.template.read_text()
for key,value in {'@VERSION@':manifest['version'],'@ARCHIVE@':manifest['archive'],
                  '@DMG@':manifest['installer'],'@SOURCE@':manifest['source'],
                  '@RELEASE_URL@':f'https://sokolovmo.ru/{args.app}'}.items():page=page.replace(key,value)
if '@VERSION@' in page or '@ARCHIVE@' in page:raise SystemExit('Unresolved template')
program=r'''
import fcntl, hashlib, json, os
from pathlib import Path
root=Path('/var/www')/APP
with (root/'.publish.lock').open('w') as lock:
    fcntl.flock(lock,fcntl.LOCK_EX)
    old=(root/'current').resolve()
    manifest=json.loads((old/'latest.json').read_text())
    if manifest['build']!=EXPECTED['build'] or manifest['sha256']!=EXPECTED['sha256']:
        raise SystemExit('Release changed; retry page publication')
    identity='site-'+str(manifest['build'])+'-'+hashlib.sha256(PAGE.encode()).hexdigest()[:16]
    target=root/'releases'/identity
    if not target.exists():
        target.mkdir(mode=0o755)
        for source in old.iterdir():
            if source.name!='index.html' and source.is_file() and not source.is_symlink():
                os.link(source,target/source.name)
        alias=target/'installer.dmg'
        alias.unlink(missing_ok=True)
        os.link(target/manifest['installer'],alias)
        (target/'index.html').write_text(PAGE)
        (target/'index.html').chmod(0o644)
    elif (target/'index.html').read_text()!=PAGE:
        raise SystemExit('Existing page identity mismatch')
    if old!=target:
        for name,destination in [('previous',old),('current',target)]:
            temporary=root/('.'+name+'-next')
            temporary.unlink(missing_ok=True)
            temporary.symlink_to(destination)
            temporary.replace(root/name)
    print('Page published:',target)
'''
program='APP='+repr(args.app)+'\nEXPECTED='+repr(manifest)+'\nPAGE='+repr(page)+'\n'+program
subprocess.run(['ssh',REMOTE,'python3','-'],input=program,text=True,check=True)
print(f'https://sokolovmo.ru/{args.app}/')
