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
 for id in ids:start(id)
 states=[ready(id) for id in ids]
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
  for minutes in [15,10,5,1]:
   msg=f'Isolated acceptance test: scheduled restart warning {minutes}m.'
   assert rpc(id,'say '+msg)=='OK';assert rpc(id,'showMessage '+msg)=='OK'
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
  start(ids[0]);after=ready(ids[0]);assert after['code'] and after['running']
 saves=[p for p in (root/'worlds'/ids[0]).rglob('*') if p.suffix in ('.db','.db2')];assert saves and saves[0].stat().st_size>0
 assert (root/'management'/ids[0]/'credential').read_bytes()==secret
 assert json.loads((scoped(ids[1])/'running.json').read_text())['pid']==records[1]['pid']
 print('PASS: graceful world save and restart, fresh join-code observation, stable credentials, unrelated server PID unchanged',flush=True)
 (root/'acceptance-result.json').write_text(json.dumps({'passed':True,'server_ids':ids,'versions':[json.loads(ctl('management-info',id))['version'] for id in ids],'join_code_observed':bool(after['code'])},indent=2))
finally:
 for id in ids:
  try:ctl('stop',id)
  except Exception as e:print('Cleanup needs attention:',id,str(e),flush=True)
 for id,p in processes:
  try:p.wait(timeout=20)
  except subprocess.TimeoutExpired:raise RuntimeError('Test service did not exit; inspect '+str(root))
 print('Isolated test services stopped. Logs retained at',root,flush=True)
