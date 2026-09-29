#!/usr/bin/env python3
"""Run one private disposable native server at a time; never register launchd jobs."""
import json,os,pathlib,re,shutil,signal,socket,subprocess,tempfile,time,uuid
os.umask(0o077)
binary=pathlib.Path(os.environ['VSM_TEST_BINARY']).resolve()
source=pathlib.Path(os.environ['VSM_TEST_RUNTIME']).resolve()
steam=pathlib.Path(os.environ['VSM_TEST_STEAMCMD']).resolve()
package=pathlib.Path(os.environ['VSM_TEST_PACKAGE']).resolve()
helper=pathlib.Path(os.environ['VSM_AUDIT_HELPER']).resolve()
catalog=pathlib.Path(os.environ['VSM_CATALOG_AUDIT']).resolve()
plan=json.loads(pathlib.Path(os.environ['VSM_INSTALL_REPORT']).read_text())
limit=int(os.environ.get('VSM_LIVE_LIMIT','500'))
startup_timeout=int(os.environ.get('VSM_LIVE_STARTUP_TIMEOUT','150'))
plan=sorted(plan,key=lambda x: (0 if x['package']=='Therzie-Warfare' else 1 if x['package']=='Advize-PlantEverything' else 2,-x['downloads']))[:limit]
report=pathlib.Path(os.environ.get('VSM_LIVE_REPORT','/tmp/vsm-top500-live.json'))
previous=json.loads(report.read_text()) if report.exists() else None
workspace=pathlib.Path(previous['workspace']) if previous else pathlib.Path(tempfile.mkdtemp(prefix='vsm-live-mod-audit-'))
results=previous['results'] if previous else []
completed={r['package'] for r in results}
plan=[r for r in plan if r['package'] not in completed]
active=None;active_root=None;active_id=None;active_env=None
def log_errors(text):
 return list(dict.fromkeys(x[:2000] for x in text.splitlines() if re.search(r'\[\s*(?:Error|Fatal)\s*:|\b[A-Za-z]*Exception:',x)))
def classify(row,baseline):
 # Loading is not sufficient: initialization and patching errors can occur before our plugin starts.
 errors=[e for e in row.get('log_errors',[]) if e not in baseline.get('log_errors',[])]
 row['new_runtime_errors']=errors
 if errors and row['result'] in ('pass','runtime_not_confirmed'):row['result']='runtime_errors'
 return row
print('Workspace:',workspace,flush=True)
def clone(src,dst):
 dst.parent.mkdir(parents=True,exist_ok=True);subprocess.run(['/bin/cp','-cR',str(src),str(dst)],check=True)
def ctl(env,action,*args,data=None,timeout=150):
 r=subprocess.run([str(binary),'--control',action,*args],env=env,input=json.dumps(data) if data is not None else None,text=True,capture_output=True,timeout=timeout)
 if r.returncode:raise RuntimeError(r.stdout+r.stderr)
 return r.stdout.strip()
def scoped(root,id):
 db=json.loads((root/'profiles.json').read_text());return root if db.get('legacyProfile')==id else root/'servers'/id

def stop():
 global active
 if active is None:return
 try:ctl(active_env,'stop',active_id,timeout=50)
 except Exception:pass
 try:active.wait(timeout=10)
 except subprocess.TimeoutExpired:
  active.terminate()
  try:active.wait(timeout=10)
  except subprocess.TimeoutExpired:active.kill();active.wait()
 # Fallback is restricted to this disposable root's recorded executable.
 record=scoped(active_root,active_id)/'running.json'
 if record.exists():
  r=json.loads(record.read_text()); exe=r.get('executable','')
  if exe.startswith(str(active_root)+'/'):
   cmd=subprocess.run(['/bin/ps','-p',str(r['pid']),'-o','command='],capture_output=True,text=True).stdout
   if exe in cmd:
    os.kill(r['pid'],signal.SIGTERM);time.sleep(2)
    cmd=subprocess.run(['/bin/ps','-p',str(r['pid']),'-o','command='],capture_output=True,text=True).stdout
    if exe in cmd:os.kill(r['pid'],signal.SIGKILL)
 active=None

def run(name,baseline=None):
 global active,active_root,active_id,active_env
 # Refuse to collide with any existing service, including production servers.
 for port in range(29856,29859):
  with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as check:check.bind(('0.0.0.0',port))
 root=workspace/('case-'+uuid.uuid4().hex[:10]);root.mkdir()
 env=dict(os.environ,VSM_HOME=str(root),VSM_MANAGEMENT_PACKAGE=str(package))
 for part in ['valheim_server','steamapps']:clone(source/part,root/'runtime/server'/part)
 clone(steam,root/'runtime/steamcmd')
 form=json.loads(ctl(env,'default-profile'));form.update(label='Isolated mod audit',name='Private mod audit',world='AuditWorld',port=29856,public=False,crossplay=False,password='isolated-audit-only')
 id=ctl(env,'save-profile',data=form)
 db=json.loads((root/'profiles.json').read_text());db['profileAutostart']={id:True};(root/'profiles.json').write_text(json.dumps(db))
 if baseline:
  target=root/'worlds'/id;shutil.rmtree(target);clone(baseline,target)
 row={'package':name or 'baseline','root':str(root)};started=time.monotonic()
 try:
  if name:
   phase='install';r=subprocess.run([str(helper),'install',str(catalog),str(root),id,name],capture_output=True,text=True,timeout=240)
   if r.returncode:raise RuntimeError('Install: '+r.stderr[-4000:])
   row['installed']=json.loads(r.stdout)
  active_root,active_id,active_env=root,id,env
  output=(root/'service.out').open('w')
  active=subprocess.Popen([str(binary),'--service',id],env=env,stdout=output,stderr=subprocess.STDOUT);output.close()
  deadline=time.monotonic()+startup_timeout;online_since=None;inventory=None
  while time.monotonic()<deadline:
   if active.poll() is not None:raise RuntimeError('Server process exited: '+(root/'service.out').read_text()[-2500:])
   r=subprocess.run([str(helper),'inventory',str(catalog),str(root),id],capture_output=True,text=True,timeout=15)
   if r.returncode==0:
    inventory=json.loads(r.stdout)
    if inventory['state']=='Online' and inventory['freshLog']:
     if online_since is None:online_since=time.monotonic()
     if time.monotonic()-online_since>=10:break
   time.sleep(1)
  else:raise RuntimeError(f'Startup timeout ({startup_timeout} seconds); last status: '+str(inventory))
  row['inventory']=inventory
  fleet=json.loads(ctl(env,'status'))
  row['serverListEntry']=next((s for s in fleet['servers'] if s['selected']==id),None)
  if not row['serverListEntry'] or row['serverListEntry']['state']!='Online':raise RuntimeError('Server missing or not Online in manager server list')
  if name and not inventory['mods']:raise RuntimeError('Installed mod missing from manager inventory')
  states=[x['status'] for x in inventory['mods']]
  row['result']='pass' if all(x=='Running' for x in states) else 'runtime_not_confirmed'
  if not name:row['result']='pass'
 except Exception as e:row['result']='failed';row['error']=str(e)
 finally:
  stop();row['seconds']=round(time.monotonic()-started,1)
  log_pointer=scoped(root,id)/'latest-log'
  if log_pointer.exists():
   log=pathlib.Path(log_pointer.read_text())
   if log.exists():
    text=log.read_text(errors='replace');row['log_errors']=log_errors(text)
    logdir=workspace/'logs';logdir.mkdir(exist_ok=True);saved=logdir/((name or 'baseline')+'.log');shutil.copy2(log,saved);row['log']=str(saved)
  # Preserve loader/console evidence too: plugins can fail before telemetry is ready.
  extra=[]
  for candidate in sorted(root.rglob('*.log')):
   if candidate.name == 'LogOutput.log' or candidate.name.startswith('console-'):
    extra.append(candidate)
  service=root/'service.out'
  if service.exists():extra.append(service)
  for index,candidate in enumerate(extra):
   logdir=workspace/'logs';logdir.mkdir(exist_ok=True)
   saved=logdir/((name or 'baseline')+f'.extra-{index}.log')
   shutil.copy2(candidate,saved)
   row.setdefault('additional_logs',[]).append(str(saved))
   row['log_errors']=list(dict.fromkeys(row.get('log_errors',[])+log_errors(candidate.read_text(errors='replace'))))
  if not name:
   template=workspace/'world-template';clone(root/'worlds'/id,template)
  shutil.rmtree(root)
 return row

def interrupted(*_):raise KeyboardInterrupt()
signal.signal(signal.SIGTERM,interrupted);signal.signal(signal.SIGINT,interrupted)
try:
 base=previous['baseline'] if previous else run(None)
 if previous:
  for row in [base]+results:
   logs=([row['log']] if row.get('log') else [])+row.get('additional_logs',[])
   row['log_errors']=list(dict.fromkeys(e for log in logs if pathlib.Path(log).exists() for e in log_errors(pathlib.Path(log).read_text(errors='replace'))))
  for row in results:classify(row,base)
  report.write_text(json.dumps({'workspace':str(workspace),'baseline':base,'results':results},indent=2))
 print('BASELINE',base['result'],base.get('error',''),flush=True)
 if base['result']!='pass':raise RuntimeError('Baseline server failed')
 for item in plan:
  row=classify(run(item['package'],workspace/'world-template'),base);results.append(row)
  tmp=report.with_suffix('.tmp');tmp.write_text(json.dumps({'workspace':str(workspace),'baseline':base,'results':results},indent=2));tmp.replace(report)
  print(len(results),row['package'],row['result'],row['seconds'],flush=True)
finally:stop()
