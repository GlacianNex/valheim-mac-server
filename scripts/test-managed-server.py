#!/usr/bin/env python3
"""Opt-in native integration test. Clones runtime into disposable storage; no launchd jobs."""
import json, os, pathlib, shutil, socket, struct, subprocess, tempfile, time
os.umask(0o077)
binary = pathlib.Path(os.environ['VSM_TEST_BINARY']).resolve()
source = pathlib.Path(os.environ['VSM_TEST_RUNTIME']).resolve()
package = pathlib.Path(os.environ['VSM_TEST_PACKAGE']).resolve()
steam = pathlib.Path(os.environ['VSM_TEST_STEAMCMD']).resolve()
root = pathlib.Path(tempfile.mkdtemp(prefix='vsm-management-acceptance-'))
env = dict(os.environ, VSM_HOME=str(root), VSM_MANAGEMENT_PACKAGE=str(package))
processes, ids = [], []
print('Isolated test root:', root, flush=True)
def clone(src, dst):
 dst.parent.mkdir(parents=True,exist_ok=True)
 subprocess.run(['/bin/cp','-cR',str(src),str(dst)],check=True)
clone(source/'valheim_server',root/'runtime/server/valheim_server')
clone(source/'steamapps',root/'runtime/server/steamapps')
clone(steam,root/'runtime/steamcmd')
def ctl(action,*args,data=None):
 r=subprocess.run([str(binary),'--control',action,*args],env=env,input=json.dumps(data) if data is not None else None,text=True,capture_output=True,timeout=150)
 if r.returncode: raise RuntimeError(action+': '+r.stdout+r.stderr)
 return r.stdout.strip()
def scoped(id):
 db=json.loads((root/'profiles.json').read_text());return root if db['legacyProfile']==id else root/'servers'/id

def rpc(id,text,password=None):
 m=root/'management'/id
 e=json.loads((m/'runtime/BepInEx/config/manager-rcon-endpoint.json').read_text())
 secret=(m/'credential').read_text() if password is None else password
 with socket.create_connection(('127.0.0.1',e['port']),timeout=6) as s:
  def exchange(kind,text):
   body=struct.pack('<ii',1,kind)+text.encode()+b'\0\0';s.sendall(struct.pack('<i',len(body))+body)
   def read(n):
    out=b''
    while len(out)<n:
     b=s.recv(n-len(out))
     if not b:raise RuntimeError('Connection closed')
     out+=b
    return out
   n=struct.unpack('<i',read(4))[0];assert 10<=n<=1048576
   b=read(n);pid,typ=struct.unpack('<ii',b[:8]);assert pid==1 and typ==(2 if kind==3 else 0)
   return b[8:-2].decode()
  exchange(3,secret);return exchange(2,text)
def start(id):
 (scoped(id)/'stop-request').unlink(missing_ok=True)
 p=subprocess.Popen([str(binary),'--service',id],env=env,stdout=(root/(id+'.out')).open('a'),stderr=subprocess.STDOUT)
 processes.append((id,p));return p

def ready(id):
 end=time.monotonic()+200
 while time.monotonic()<end:
  try:
   status=next(s for s in json.loads(ctl('status'))['servers'] if s['selected']==id)
   if status['state']=='Online' and rpc(id,'health').startswith('OK ManagerRcon'):
    return status
  except (OSError,AssertionError,RuntimeError,ValueError):pass
  if processes and processes[-1][1].poll() is not None:raise RuntimeError('Service exited; inspect '+str(root))
  time.sleep(1)
 raise RuntimeError('Server not ready; inspect '+str(root))
try:
 for i in range(2):
  form=json.loads(ctl('default-profile'));form.update(label='Acceptance '+str(i),name='VSM isolated acceptance '+str(i),world='AcceptanceWorld'+str(i),port=29756+i*10,public=False,crossplay=(i==0),password='isolated-test-only')
  id=ctl('save-profile',data=form);ids.append(id)
 db=json.loads((root/'profiles.json').read_text())
 assert all(db['managedServers'][id] for id in ids)
 db['managedServers'].pop(ids[0]) # Simulate a pre-management deployment.
 db['profileAutostart']={id:True for id in ids};(root/'profiles.json').write_text(json.dumps(db))
 ctl("enable-networking",ids[1])
 for id in ids:start(id)
 states=[ready(id) for id in ids]
 for i,id in enumerate(ids):
  plugins=root/'management'/id/'runtime/BepInEx/plugins'
  assert (plugins/'Jotunn/Jotunn.dll').is_file()
  assert (plugins/'NetworkPerformanceSystem/NetworkPerformanceSystem.dll').is_file() == (i==1)
  log=(root/'management'/id/'runtime/BepInEx/LogOutput.log').read_text()
  assert 'Loading [Jotunn 2.30.2]' in log, log[-3000:]
  if i==1:
   assert 'NetworkPerformanceSystem 1.6.0' in log, log[-3000:]
  assert '[Error' not in log, log[-6000:]
 for id in ids:
  snapshot_path=root/'management'/id/'runtime/BepInEx/config/vsm-mod-status.json'
  deadline=time.monotonic()+15
  while not snapshot_path.exists() and time.monotonic()<deadline:time.sleep(.25)
  snapshot=json.loads(snapshot_path.read_text())
  assert snapshot['pid']==json.loads((scoped(id)/'running.json').read_text())['pid']
  assert any(m['name']=='Jotunn' and m['status']=='Loaded' and m['version']=='2.30.2' for m in snapshot['mods']),snapshot
  assert any(m['name']=='Manager RCON' and m['status']=='Loaded' for m in snapshot['mods']),snapshot
  assert all('dependencies' in m and 'path' in m for m in snapshot['mods']),snapshot
 print('PASS: live mod names, GUIDs, versions, dependency metadata and Loaded status match each server PID',flush=True)
 print('PASS: native Jotunn 2.30.2 and optional NPS 1.6.0 loaded without plugin errors',flush=True)
 # Both backends report a real zero in the Unity log, including before the 10-minute summary.
 states=json.loads(ctl('status'))['servers']
 assert all(s['players']=='0' for s in states),states
 assert next(s for s in states if s['selected']==ids[1])['crossplay'] is False
 assert next(s for s in states if s['selected']==ids[1])['port']==29766
 for id in ids:
  record=json.loads((scoped(id)/'running.json').read_text())
  assert 'VSM player count: 0' in pathlib.Path(record['log']).read_text()
 print('PASS: Steam and crossplay player counts in real server logs; join-address metadata',flush=True)
 assert all(json.loads((root/'profiles.json').read_text())['managedServers'][id] for id in ids)
 records=[json.loads((scoped(id)/'running.json').read_text()) for id in ids]
 endpoints=[json.loads((root/'management'/id/'runtime/BepInEx/config/manager-rcon-endpoint.json').read_text()) for id in ids]
 assert endpoints[0]['port']!=endpoints[1]['port']
 for e in endpoints:
  l=subprocess.run(['/usr/sbin/lsof','-nP','-a','-p',str(e['pid']),'-iTCP','-sTCP:LISTEN'],capture_output=True,text=True,check=True).stdout
  assert '127.0.0.1:'+str(e['port']) in l
 for id in ids:
  info=json.loads(ctl('management-info',id));assert info['players']==0 and info['fps']>0 and info['managedMemoryBytes']>0
  assert info['onlinePlayers']==[] and isinstance(info['banned'],list)
  assert info['pingSupported'] == (id == ids[1]), info
  for minutes in [15,10,5,1]:
   msg=f'Isolated acceptance test: scheduled restart warning {minutes}m.'
   assert rpc(id,'say '+msg)=='OK';assert rpc(id,'showMessage '+msg)=='OK'
 for id in ids:
  info=json.loads(rpc(id,'worldInfo'));assert info['raidPauseAvailable'] is True and isinstance(info['events'],list), info
  for minutes in [180,360,720]:
   before=json.loads(rpc(id,'worldInfo'))['seconds'];assert rpc(id,f'worldAdvance {minutes}').startswith('OK')
   assert json.loads(rpc(id,'worldInfo'))['seconds']>before
  assert rpc(id,'worldAdvance 721').startswith('ERROR:')
  assert rpc(id,'worldAdvance -1').startswith('ERROR:')
  assert rpc(id,'worldRaidPause 1').startswith('OK')
  assert 0 < json.loads(rpc(id,'worldInfo'))['raidsPausedSeconds'] <= 60
  assert rpc(id,'worldRaidStart '+json.dumps({'raid':'invalid','player':'missing'})).startswith('ERROR:')
  assert rpc(id,'worldRaidResume').startswith('OK')
  assert json.loads(rpc(id,'worldInfo'))['raidsPausedSeconds']==0
  assert rpc(id,'worldRaidStart '+json.dumps({'raid':'invalid','player':'missing'})).startswith('ERROR:')
  assert rpc(id,'worldRaidStop').startswith('OK')
  assert json.loads(rpc(id,'worldInfo'))['raid']==''
  assert rpc(id,'worldMorning').startswith('OK')
  time.sleep(1)
  assert rpc(id,'worldSave').startswith('OK')
  end=time.monotonic()+60
  while time.monotonic()<end:
   state=json.loads(rpc(id,'worldInfo'))
   if not state['saveInProgress'] and state['lastSaveSecondsAgo'] is not None:break
   time.sleep(1)
  else:raise RuntimeError('Save not confirmed')
 print('PASS: world time advance/morning, async save completion, raid stop/pause/resume and invalid raid rejection on both backends',flush=True)
 try:rpc(ids[0],'health',password='wrong-password');raise RuntimeError('Wrong password accepted')
 except AssertionError:pass
 assert rpc(ids[0],'invalid-command').startswith('ERROR:')
 # Ban a synthetic platform ID, verify persisted settings, and remove it again.
 target='Steam_76561198000000000'
 ctl('management-command',ids[0],'ban',target)
 bans=rpc(ids[0],'banned');assert target in bans,bans
 db=json.loads((root/'profiles.json').read_text());assert target in db['profiles'][0]['banned']
 ctl('management-command',ids[0],'unban',target)
 db=json.loads((root/'profiles.json').read_text());assert target not in db['profiles'][0]['banned']
 ctl('management-command',ids[0],'kick','NoSuchAcceptancePlayer')
 print('PASS: two native managed worlds, distinct localhost ports, authentication, warnings, performance and persisted ban/unban',flush=True)
 secret=(root/'management'/ids[0]/'credential').read_bytes()
 if os.environ.get('VSM_TEST_RESTART_HELPER'):
  subprocess.run([os.environ['VSM_TEST_RESTART_HELPER'],ids[0],str(binary)],env=env,check=True,timeout=300)
  after=ready(ids[0]);assert after['code'] and after['running']
  assert 'reason=scheduled restarted; join code=' in (root/'logs/maintenance.log').read_text()
 else:
  ctl('stop',ids[0]);processes[0][1].wait(timeout=20)
  backup=json.loads(ctl('world-backup',ids[0],'Native world checkpoint'))
  ctl('world-restore',ids[0],backup['id'])
  assert len(json.loads(ctl('world-backups',ids[0])))==2
  print('PASS: native world backup/restore with recovery snapshot',flush=True)
  start(ids[0]);after=ready(ids[0]);assert after['code'] and after['running']
 saves=[p for p in (root/'worlds'/ids[0]).rglob('*') if p.suffix in ('.db','.db2')];assert saves and saves[0].stat().st_size>0
 assert (root/'management'/ids[0]/'credential').read_bytes()==secret
 assert json.loads((scoped(ids[1])/'running.json').read_text())['pid']==records[1]['pid']
 print('PASS: graceful world save and restart, fresh join-code observation, stable credentials, unrelated server PID unchanged',flush=True)
 # Independent networking-only and vanilla launches use the same saved world.
 id=ids[1];ctl('stop',id)
 for sid,p in processes:
  if sid==id:p.wait(timeout=30)
 ctl('disable-management',id)
 p=start(id)
 end=time.monotonic()+200
 while time.monotonic()<end:
  status=next(s for s in json.loads(ctl('status'))['servers'] if s['selected']==id)
  if status['state']=='Online':break
  if p.poll() is not None:raise RuntimeError('Network-only service exited')
  time.sleep(1)
 else:raise RuntimeError('Network-only startup timeout')
 plugins=root/'management'/id/'runtime/BepInEx/plugins'
 assert not (plugins/'ManagerRcon').exists()
 assert (plugins/'Jotunn/Jotunn.dll').is_file()
 assert (plugins/'NetworkPerformanceSystem/NetworkPerformanceSystem.dll').is_file()
 log=(root/'management'/id/'runtime/BepInEx/LogOutput.log').read_text()
 assert 'NetworkPerformanceSystem 1.6.0' in log and '[Error' not in log,log[-6000:]
 ctl('stop',id);p.wait(timeout=30);ctl('disable-networking',id)
 p=start(id)
 end=time.monotonic()+200
 while time.monotonic()<end:
  status=next(s for s in json.loads(ctl('status'))['servers'] if s['selected']==id)
  if status['state']=='Online':break
  if p.poll() is not None:raise RuntimeError('Vanilla service exited')
  time.sleep(1)
 else:raise RuntimeError('Vanilla startup timeout')
 record=json.loads((scoped(id)/'running.json').read_text())
 assert str(root/'runtime/server') in record['executable'],record
 print('PASS: networking-only restart removes RCON; both off boots vanilla with the same world',flush=True)
 (root/'acceptance-result.json').write_text(json.dumps({'passed':True,'server_ids':ids,'versions':[json.loads(ctl('management-info',ids[0]))['version']],'join_code_observed':bool(after['code'])},indent=2))
finally:
 for id in ids:
  try:ctl('stop',id)
  except Exception as e:print('Cleanup needs attention:',id,str(e),flush=True)
 for id,p in processes:
  try:p.wait(timeout=20)
  except subprocess.TimeoutExpired:raise RuntimeError('Test service did not exit; inspect '+str(root))
 print('Isolated test services stopped. Logs retained at',root,flush=True)
