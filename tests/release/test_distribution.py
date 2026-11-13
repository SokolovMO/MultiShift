"""Exercise real release signatures and tampering failures, using ephemeral keys."""
import base64
import hashlib
import importlib.util
import json
import plistlib
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

scripts = Path(__file__).resolve().parents[2] / 'scripts'
sys.path.insert(0, str(scripts))
from build_release import feed, key_material, release_url, sign
from publish_release import verify

SPARKLE = Path('/tmp/multishift-sparkle-2.10.0')


class DistributionTests(unittest.TestCase):
    def test_host_bundle_declares_both_languages_for_sparkle(self):
        script = (scripts / 'build_macos.sh').read_text()
        plist = script.split('<?xml version="1.0" encoding="UTF-8"?>', 1)[1].split('\nPLIST', 1)[0]
        info = plistlib.loads(('<?xml version="1.0" encoding="UTF-8"?>' + plist).encode())
        self.assertEqual(set(info['CFBundleLocalizations']), {'ru', 'en'})

    def test_feed_notes_are_localized_and_link_to_source(self):
        document = ET.fromstring(feed('0.3.0', '5', 'https://sokolovmo.ru/multishift/',
                                     'app.zip', 'signature', 42, 'source.tar.gz'))
        notes = {node.get('{http://www.w3.org/XML/1998/namespace}lang'): node.text
                 for node in document.findall('./channel/item/description')}
        self.assertEqual(set(notes), {'ru', 'en'})
        self.assertTrue(all('source.tar.gz' in text for text in notes.values()))
        self.assertIn('Homebrew', notes['ru'])

    def test_reject_unsafe_release_addresses(self):
        for value in ['http://host/app', 'https://user:secret@host/app', 'https://host/app?token=1', 'https://host/app#part']:
            with self.assertRaises(ValueError):
                release_url(value)
        self.assertEqual(release_url('https://host/app'), 'https://host/app/')

    @unittest.skipUnless((SPARKLE / 'bin/sign_update').exists(), 'requires verified Sparkle tools')
    def test_signed_release_rejects_archive_feed_and_source_tampering(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            seed = root / 'test.seed'
            seed.write_bytes(bytes(range(32)))
            public, key = key_material(seed.read_bytes())
            directory = root / 'release'
            directory.mkdir()
            archive = directory / 'MultiShift-0.3.0-2-arm64.zip'
            archive.write_bytes(b'archive fixture')
            signature = sign(SPARKLE / 'bin/sign_update', key, archive)
            dmg = directory / 'MultiShift-0.3.0-2-arm64.dmg'
            dmg.write_bytes(b'installer fixture')
            dmg_signature = sign(SPARKLE / 'bin/sign_update', key, dmg)
            source = directory / 'source.tar.gz'
            source.write_bytes(b'source fixture')
            for name in ['index.html', 'install.sh', 'LICENSE', 'THIRD-PARTY-NOTICES.md']:
                (directory / name).write_text('fixture')
            (directory / 'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in [archive, dmg, source]))
            manifest = dict(version='0.3.0', build=2, archive=archive.name, bytes=archive.stat().st_size,
                            sha256=hashlib.sha256(archive.read_bytes()).hexdigest(), updater_public_key=public, source=source.name,
                            installer=dmg.name, installer_bytes=dmg.stat().st_size,
                            installer_sha256=hashlib.sha256(dmg.read_bytes()).hexdigest(), installer_signature=dmg_signature)
            (directory / 'latest.json').write_text(json.dumps(manifest))
            appcast = directory / 'appcast.xml'
            appcast.write_bytes(feed('0.3.0', '2', 'https://sokolovmo.ru/multishift/', archive.name, signature, archive.stat().st_size, source.name))
            sign(SPARKLE / 'bin/sign_update', key, appcast)
            self.assertEqual(verify(directory, seed, SPARKLE)['build'], 2)
            media = directory / 'multishift-demo.mp4'
            shutil.copyfile(scripts.parent / 'release-site' / media.name, media)
            self.assertEqual(verify(directory, seed, SPARKLE)['build'], 2)
            media.write_bytes(b'changed public video')
            with self.assertRaisesRegex(ValueError, 'public media differs'):
                verify(directory, seed, SPARKLE)
            media.unlink()
            unexpected = directory / 'unreviewed-video.mp4'
            unexpected.write_bytes(b'unreviewed extra')
            with self.assertRaisesRegex(ValueError, 'unexpected distribution file'):
                verify(directory, seed, SPARKLE)
            unexpected.unlink()
            original_dmg = dmg.read_bytes()
            dmg.write_bytes(b'changed installer')
            with self.assertRaises(ValueError):
                verify(directory, seed, SPARKLE)
            dmg.write_bytes(original_dmg)
            original = archive.read_bytes()
            archive.write_bytes(b'changed archive')
            with self.assertRaises(ValueError):
                verify(directory, seed, SPARKLE)
            archive.write_bytes(original)
            original_feed = appcast.read_bytes()
            appcast.write_bytes(original_feed.replace(b'<title>MultiShift</title>', b'<title>Changed</title>'))
            with self.assertRaises(subprocess.CalledProcessError):
                verify(directory, seed, SPARKLE)
            appcast.write_bytes(original_feed)
            source.write_bytes(b'changed source')
            with self.assertRaises(ValueError):
                verify(directory, seed, SPARKLE)

    def test_invalid_seed_fails_without_rotation(self):
        with self.assertRaises(ValueError):
            key_material(b'invalid')
