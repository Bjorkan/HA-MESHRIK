#!/usr/bin/env python3
"""Offline checks of the wrapper contract with the MESHRIK #48/#49 config."""
from pathlib import Path
import json
import re
import yaml

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {
    'startup_policy': ('sync', 'list(passive|sync|full)'),
    'passive_startup': (False, 'bool'),
    'startup_export_private_key': (False, 'bool'),
    'startup_sync_clock': (False, 'bool'),
    'startup_apply_flood_scope': (False, 'bool'),
    'startup_send_advertisement': (False, 'bool'),
    'startup_drain_messages': (False, 'bool'),
    'startup_reconcile_contacts': (False, 'bool'),
    'startup_clear_channel_slots': (False, 'bool'),
    'startup_allow_periodic_offload': (False, 'bool'),
    'startup_enable_telemetry_collection': (False, 'bool'),
    'auto_reboot_on_clock_skew': (False, 'bool'),
    'login_response_timeout_seconds': (5, 'int'),
}

assert not (ROOT / 'remoteterm').exists()
assert not (ROOT / 'remoteterm-dev').exists()
for directory, slug, package in (
    ('meshrik', 'meshrik', 'meshrik-app'),
    ('meshrik-dev', 'meshrik-dev', 'meshrik-app-dev'),
):
    path = ROOT / directory
    config = yaml.safe_load((path / 'config.yaml').read_text())
    lock = json.loads((path / 'source-lock.json').read_text())
    script = (path / 'run.sh').read_text()
    assert config['slug'] == slug
    assert config['image'] == f'ghcr.io/bjorkan/ha-meshrik/{package}'
    assert config['version'] == lock['wrapper_version']
    assert config['options'].keys() == config['schema'].keys()
    assert config['options']['skip_post_connect_sync'] is False
    for key, (value, schema) in EXPECTED.items():
        assert config['options'][key] == value, (directory, key)
        assert config['schema'][key] == schema, (directory, key)
        assert f'MESHCORE_{key.upper()}' in script, key
    assert f'context: {directory}/' in (ROOT / '.github/workflows' /
                                      ('build-publish-dev.yml' if slug.endswith('dev') else 'build-publish.yml')).read_text()
    assert lock['wrapper_image'] in {
        config['image'],
        f'ghcr.io/bjorkan/ha-meshrik/{"remoteterm-app-dev" if slug.endswith("dev") else "remoteterm-app"}',
    }, 'Only the last published legacy wrapper or the current one is a valid lock'
    assert re.fullmatch(r'sha256:[0-9a-f]{64}', lock['source_digest'])
    assert re.fullmatch(r'sha256:[0-9a-f]{64}', lock['wrapper_digest'])
assert (ROOT / 'meshrik/run.sh').read_bytes() == (ROOT / 'meshrik-dev/run.sh').read_bytes()
print('HA manifests, upstream startup-policy mapping and renamed paths: PASS')
