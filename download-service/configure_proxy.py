"""Add only the two product counter routes to the confirmed existing nginx."""
import subprocess
program = r"""
from pathlib import Path
import datetime, json, shutil, subprocess
config=Path('/etc/nginx/sites-available/sokolovmo.ru')
snippet=Path('/etc/nginx/snippets/multi-downloads.conf')
subprocess.run(['nginx','-t'],check=True)
paths=['/workshop/','/finbot/','/site1/','/site2/','/site3/','/site4/','/site5/','/site6/','/v6/']
def statuses():
    return {p:subprocess.check_output(['curl','-sS','--max-time','15','--resolve','sokolovmo.ru:443:127.0.0.1','-o','/dev/null','-w','%{http_code}','https://sokolovmo.ru'+p],text=True) for p in paths}
before=statuses()
backup=Path('/var/backups/multi-downloads')/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ-proxy')
backup.mkdir(parents=True)
shutil.copy2(config,backup/'sokolovmo.ru')
old_snippet=snippet.read_bytes() if snippet.exists() else None
if old_snippet is not None:(backup/'multi-downloads.conf').write_bytes(old_snippet)
blocks=[]
for app,name in [('multishift','MultiShift'),('multiswitcher','MultiSwitcher')]:
    for endpoint in ['download','download-count.json']:
        fallback=f'        proxy_intercept_errors on;\n        error_page 502 503 504 = @{app}_download_fallback;\n' if endpoint=='download' else ''
        blocks.append(f'''    location = /{app}/{endpoint} {{
        proxy_pass http://127.0.0.1:8097;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_connect_timeout 2s;
        proxy_read_timeout 8s;
        access_log off;
{fallback}    }}
''')
    blocks.append(f'''    location @{app}_download_fallback {{
        root /var/www/{app}/current;
        try_files /installer.dmg =503;
        add_header Content-Disposition 'attachment; filename="{name}.dmg"' always;
        add_header Cache-Control no-store always;
        access_log off;
    }}
''')
original=config.read_text()
include='    include /etc/nginx/snippets/multi-downloads.conf;'
anchor='    location ^~ /air { return 404; }'
assert original.count(anchor)==1
try:
    snippet.write_text('\n'.join(blocks))
    if include not in original:config.write_text(original.replace(anchor,include+'\n\n'+anchor))
    subprocess.run(['nginx','-t'],check=True)
    subprocess.run(['systemctl','reload','nginx'],check=True)
    after=statuses()
    if before!=after:raise RuntimeError(f'Routes changed: {before} -> {after}')
except BaseException:
    config.write_text(original)
    if old_snippet is None:snippet.unlink(missing_ok=True)
    else:snippet.write_bytes(old_snippet)
    subprocess.run(['nginx','-t'],check=True)
    subprocess.run(['systemctl','reload','nginx'],check=True)
    raise
(backup/'route-check.json').write_text(json.dumps({'before':before,'after':after},indent=2))
print('Proxy configured; backup:',backup,'preserved routes:',before)
"""
subprocess.run(['ssh','vyrex_nl_project','python3','-'],input=program,text=True,check=True)
