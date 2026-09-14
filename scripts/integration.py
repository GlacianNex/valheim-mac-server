#!/usr/bin/env python3
"""Opt-in native lifecycle test. Uses a disposable root and never registers launch agents."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--binary', required=True, type=Path)
parser.add_argument('--root', required=True, type=Path)
parser.add_argument('--runtime', required=True, type=Path, help='Existing app-managed runtime folder containing server/ and steamcmd/')
parser.add_argument('--port', type=int, default=25456)
args = parser.parse_args()
root = args.root.resolve()
assert not root.exists(), 'Use a new empty root. This test will not reuse profiles.'
root.mkdir(parents=True)
(root / 'runtime').symlink_to(args.runtime.resolve(), target_is_directory=True)
env = dict(os.environ, VSM_HOME=str(root))
binary = str(args.binary.resolve())
def control(action, value=None):
    result = subprocess.run([binary, '--control', action], input=json.dumps(value) if value is not None else None,
                            text=True, capture_output=True, env=env, check=True)
    return result.stdout
profile = json.loads(control('default-profile'))
profile.update(label='Integration fixture', name='Integration fixture', world='IntegrationFixture',
               password='integration-only-password', port=args.port, public=False, crossplay=True)
control('save-profile', profile)
database = json.loads((root / 'profiles.json').read_text())
database['autostart'] = True
database['profileAutostart'] = {database['selected']: True}
(root / 'profiles.json').write_text(json.dumps(database))
logs = []
for cycle in range(2):
    (root / 'stop-request').unlink(missing_ok=True)
    service = subprocess.Popen([binary, '--service'], env=env)
    try:
        deadline = time.monotonic() + 180
        while time.monotonic() < deadline:
            if service.poll() is not None:
                raise RuntimeError('Native service exited before becoming ready: ' + control('status'))
            status = json.loads(control('status'))
            if status['state'] == 'Online' and status['code']:
                break
            time.sleep(1)
        else:
            raise RuntimeError('Timed out waiting for the crossplay session')
        assert status['players'] == '0'
        print(f'Cycle {cycle + 1}: native crossplay server online with zero players', flush=True)
    finally:
        control('stop')
        service.wait(timeout=130)
    assert service.returncode == 0
    log = Path((root / 'latest-log').read_text()).read_text(errors='replace')
    assert 'World save (5/5) done' in log, 'No completed world-save marker'
    logs.append(log)
    assert not json.loads(control('status'))['running']
    print(f'Cycle {cycle + 1}: clean shutdown and all save stages completed', flush=True)
assert 'ZDOMan.LoadChunks => Loading ZDOs done' in logs[1], 'Saved world was not loaded'
assert 'Save number 2' in logs[1], 'Expected the second save of the same world'
assert list((root / 'worlds').rglob('*.fwl2')) or list((root / 'worlds').rglob('*.fwl'))
print('PASS: install-independent native lifecycle, save, and restart test. Fixture retained at', root)
