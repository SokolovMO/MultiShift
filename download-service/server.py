#!/usr/bin/env python3
"""Private loopback service: count download starts, never installations or people."""
import argparse
from datetime import datetime, timezone
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import secrets
import sqlite3
import threading
import time
from urllib.parse import quote, urlsplit

APPS = {'multishift': Path('/var/www/multishift/current'),
        'multiswitcher': Path('/var/www/multiswitcher/current')}


class Counter:
    def __init__(self, database, apps=None, now=time.monotonic):
        self.database = str(database)
        self.apps = apps or APPS
        self.now = now
        self.secret = secrets.token_bytes(32)
        self.recent = {}
        self.lock = threading.Lock()
        with sqlite3.connect(self.database) as db:
            db.execute('CREATE TABLE IF NOT EXISTS starts (app TEXT, day TEXT, build INTEGER, count INTEGER NOT NULL, PRIMARY KEY(app,day,build))')
            db.execute('CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT)')
            db.execute('INSERT OR IGNORE INTO metadata VALUES (?,?)', ('since', datetime.now(timezone.utc).isoformat()))

    def release(self, app):
        root = self.apps[app]
        manifest = json.loads((root / 'latest.json').read_text())
        name = manifest['installer']
        if Path(name).name != name or not name.endswith('-arm64.dmg') or not (root / name).is_file():
            raise ValueError('installer unavailable')
        return manifest

    def start(self, app, build, address, agent):
        # No cookies or persistent client identifiers. Short-lived random-key hashes only deduplicate
        # retries in RAM. Database stores daily/app/build totals, never IP or UA.
        if any(word in agent.lower() for word in ('bot', 'crawler', 'spider', 'preview')):
            return
        digest = hmac.new(self.secret, f'{app}:{build}:{address}:{agent[:512]}'.encode(), hashlib.sha256).digest()
        moment = self.now()
        with self.lock:
            self.recent = {key: expiry for key, expiry in self.recent.items() if expiry > moment}
            if digest in self.recent:
                return
            if len(self.recent) >= 10000:
                self.recent.clear()
            self.recent[digest] = moment + 20 * 60
            day = datetime.now(timezone.utc).date().isoformat()
            with sqlite3.connect(self.database, timeout=5) as db:
                db.execute('INSERT INTO starts VALUES (?,?,?,1) ON CONFLICT(app,day,build) DO UPDATE SET count=count+1', (app, day, build))

    def stats(self, app):
        with sqlite3.connect(self.database, timeout=5) as db:
            total = db.execute('SELECT COALESCE(SUM(count),0) FROM starts WHERE app=?', (app,)).fetchone()[0]
            since = db.execute('SELECT value FROM metadata WHERE key=?', ('since',)).fetchone()[0]
        return {'downloads_started': total, 'since': since,
                'meaning': 'download starts via the website; not completed downloads, unique people, or installations'}


def handler(counter):
    class Handler(BaseHTTPRequestHandler):
        def do_HEAD(self):
            self.respond(head=True)

        def do_GET(self):
            self.respond(head=False)

        def respond(self, head):
            parts = urlsplit(self.path).path.strip('/').split('/')
            if len(parts) != 2 or parts[0] not in counter.apps or parts[1] not in {'download', 'download-count.json'}:
                self.send_error(404)
                return
            app, endpoint = parts
            try:
                if endpoint == 'download':
                    release = counter.release(app)
                    if not head:
                        counter.start(app, int(release['build']), self.headers.get('X-Real-IP', self.client_address[0]), self.headers.get('User-Agent', ''))
                    self.send_response(302)
                    self.send_header('Location', f'/{app}/{quote(release["installer"])}')
                    data = b''
                else:
                    data = json.dumps(counter.stats(app)).encode()
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json; charset=utf-8')
                self.send_header('Cache-Control', 'no-store')
                self.send_header('X-Content-Type-Options', 'nosniff')
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                if not head:
                    self.wfile.write(data)
            except (OSError, ValueError, KeyError, sqlite3.Error):
                self.send_error(503, 'Download temporarily unavailable')

        def log_message(self, *args):
            pass
    return Handler


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', type=Path, required=True)
    parser.add_argument('--port', type=int, default=8097)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), handler(Counter(args.database)))
    server.serve_forever()
