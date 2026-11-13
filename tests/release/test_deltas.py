"""Delta integrity, feed mapping and publication prerequisites."""
from pathlib import Path
import hashlib
import json
import sys
import xml.etree.ElementTree as ET
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from release_deltas import (add_delta_enclosures, validate_deltas, require_deltas, tree_inventory)
from build_release import feed, NS


def fixture(tmp_path):
    path = tmp_path / 'MultiShift-10-11-arm64.delta'
    path.write_bytes(b'patch fixture')
    delta = dict(from_build=10, to_build=11, archive=path.name, bytes=path.stat().st_size,
                 sha256=hashlib.sha256(path.read_bytes()).hexdigest(), signature='test-signature',
                 verified_tree_sha256='a'*64, base_archive_sha256='b'*64, sparkle_executable_bytes=941872)
    m = dict(build=11, bytes=10000, deltas=[delta])
    item = ET.fromstring(feed('0.4.1', '11', 'https://example.test/', 'app.zip', 'full-signature', 10000, 'source.tar.gz', [delta])).find('./channel/item')
    return m, item, path


def test_only_valid_matching_base_satisfies_release_policy():
    with pytest.raises(ValueError, match='current build 10'): require_deltas({'deltas': []}, 10)
    with pytest.raises(ValueError): require_deltas({'deltas': [{'from_build': 9}]}, 10)
    require_deltas({'deltas': [{'from_build': 10}]}, 10)


def test_signed_feed_maps_delta_to_exact_source_build(tmp_path):
    m, item, path = fixture(tmp_path)
    signatures = []
    names = validate_deltas(tmp_path, m, item, 'https://example.test/', lambda p, s: signatures.append((p,s)))
    assert names == {path.name} and signatures == [(path, 'test-signature')]
    assert item.find(f'{{{NS}}}deltas/enclosure').get(f'{{{NS}}}deltaFrom') == '10'
    assert item.find('enclosure').get('url') == 'https://example.test/app.zip'


@pytest.mark.parametrize('corrupt', ['patch', 'url', 'size', 'signature', 'base', 'duplicate', 'missing_proof', 'traversal'])
def test_reject_delta_and_manifest_feed_mismatch(tmp_path, corrupt):
    m,item,path = fixture(tmp_path)
    enclosure = item.find(f'{{{NS}}}deltas/enclosure')
    if corrupt == 'patch': path.write_bytes(b'tampered')
    if corrupt == 'url': enclosure.set('url','https://other.test/patch.delta')
    if corrupt == 'size': m['deltas'][0]['bytes']=m['bytes']
    if corrupt == 'signature': enclosure.set(f'{{{NS}}}edSignature','wrong')
    if corrupt == 'base': m['deltas'][0]['from_build']=11
    if corrupt == 'duplicate': m['deltas'].append(m['deltas'][0]);add_delta_enclosures(item,m['deltas'],'https://example.test/')
    if corrupt == 'missing_proof': del m['deltas'][0]['verified_tree_sha256']
    if corrupt == 'traversal': m['deltas'][0]['archive']='../patch.delta'
    with pytest.raises(ValueError): validate_deltas(tmp_path,m,item,'https://example.test/',lambda *_:None)


def test_inventory_checks_bytes_and_links_but_ignores_dates(tmp_path):
    (tmp_path/'file').write_bytes(b'one');(tmp_path/'link').symlink_to('file');(tmp_path/'empty').mkdir()
    before=tree_inventory(tmp_path)
    import os
    os.utime(tmp_path/'file',(1,1));assert tree_inventory(tmp_path)==before
    (tmp_path/'file').write_bytes(b'two');assert tree_inventory(tmp_path)!=before
    (tmp_path/'file').write_bytes(b'one');(tmp_path/'link').unlink();(tmp_path/'link').symlink_to('other')
    assert tree_inventory(tmp_path)!=before


def client_manifest(tmp_path):
    m, _, _ = fixture(tmp_path)
    d = m['deltas'][0]
    m['client_checks'] = [dict(from_build=10, to_build=11, selected_delta=True,
        binary_delta_applied_and_validated=True, patch_sha256=d['sha256'], installed=False,
        archive=d['archive'], downloaded_bytes=d['bytes'], expected_bytes=d['bytes'])]
    return m


@pytest.mark.parametrize('field,value', [('selected_delta', False), ('installed', True),
    ('downloaded_bytes', 0), ('expected_bytes', 99), ('patch_sha256', 'c'*64),
    ('archive', 'wrong.delta'), ('to_build', 12), ('binary_delta_applied_and_validated', False)])
def test_publication_rejects_wrong_client_evidence(tmp_path, field, value):
    from release_deltas import require_client_check
    m = client_manifest(tmp_path)
    require_client_check(m, 10)
    m['client_checks'][0][field] = value
    with pytest.raises(ValueError): require_client_check(m, 10)


def test_publication_requires_unique_client_report(tmp_path):
    from release_deltas import require_client_check
    m = client_manifest(tmp_path)
    m['client_checks'] *= 2
    with pytest.raises(ValueError): require_client_check(m, 10)
    m['client_checks'] = []
    with pytest.raises(ValueError): require_client_check(m, 10)


def test_metadata_refresh_preserves_immutable_artifacts_and_existing_deltas(tmp_path):
    from copy import deepcopy
    from release_deltas import validate_refresh
    m = client_manifest(tmp_path)
    old = dict(build=11, bytes=10000)
    validate_refresh(old, m)
    for key in ('build', 'bytes'):
        bad = deepcopy(m); bad[key] += 1
        with pytest.raises(ValueError): validate_refresh(old, bad)
    bad = deepcopy(m); bad['deltas'] = []
    with pytest.raises(ValueError): validate_refresh(m, bad)
    bad = deepcopy(m); bad['deltas'][0]['sha256'] = 'c'*64
    with pytest.raises(ValueError): validate_refresh(m, bad)


def test_signature_verifier_failure_is_not_ignored(tmp_path):
    m, item, _ = fixture(tmp_path)
    def reject(*args): raise ValueError('bad Ed25519 signature')
    with pytest.raises(ValueError, match='Ed25519'):
        validate_deltas(tmp_path, m, item, 'https://example.test/', reject)


@pytest.mark.parametrize('field,value', [('to_build', 12), ('sparkle_executable_bytes', 0)])
def test_reject_wrong_target_and_sparkle_precondition(tmp_path, field, value):
    m, item, _ = fixture(tmp_path)
    m['deltas'][0][field] = value
    with pytest.raises(ValueError):
        validate_deltas(tmp_path, m, item, 'https://example.test/', lambda *_: None)
