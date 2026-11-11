import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('downloads', Path(__file__).with_name('server.py'))
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)

class CounterTests(unittest.TestCase):
    def test_retries_are_deduplicated_and_versions_count_independently(self):
        with tempfile.TemporaryDirectory() as temp:
            clock = [0]
            counter = module.Counter(Path(temp)/'counts.db', now=lambda:clock[0])
            counter.start('multishift',4,'192.0.2.1','browser')
            counter.start('multishift',4,'192.0.2.1','browser')
            self.assertEqual(counter.stats('multishift')['downloads_started'],1)
            counter.start('multishift',5,'192.0.2.1','browser')
            counter.start('multiswitcher',67,'192.0.2.1','browser')
            clock[0]=1201
            counter.start('multishift',4,'192.0.2.1','browser')
            self.assertEqual(counter.stats('multishift')['downloads_started'],3)
            self.assertEqual(counter.stats('multiswitcher')['downloads_started'],1)
            counter.start('multishift',4,'192.0.2.2','health-bot')
            self.assertEqual(counter.stats('multishift')['downloads_started'],3)
            with sqlite3.connect(counter.database) as db:
                columns=[row[1] for row in db.execute('PRAGMA table_info(starts)')]
                self.assertEqual(columns,['app','day','build','count'])

    def test_redirect_follows_current_manifest_and_rejects_path_escape(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            counter=module.Counter(root/'counts.db',apps={'multishift':root})
            (root/'app-arm64.dmg').write_bytes(b'fixture')
            (root/'latest.json').write_text(json.dumps({'build':4,'installer':'app-arm64.dmg'}))
            self.assertEqual(counter.release('multishift')['build'],4)
            (root/'latest.json').write_text(json.dumps({'build':5,'installer':'../app-arm64.dmg'}))
            with self.assertRaises(ValueError):counter.release('multishift')
