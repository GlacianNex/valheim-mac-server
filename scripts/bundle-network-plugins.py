#!/usr/bin/env python3
"""Bundle reviewed versions only. Never resolve 'latest' during a release build."""
import hashlib, json, pathlib, subprocess, zipfile
cache = pathlib.Path('.build/network-packages'); cache.mkdir(parents=True, exist_ok=True)
out = pathlib.Path('dist/Management')
def fetch(name, url, digest):
    path = cache / name
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        subprocess.run(['curl','--fail','--location','--proto','=https','--tlsv1.2',url,'-o',str(path)],check=True)
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest: raise RuntimeError('Checksum mismatch: '+name)
    return path
packages = [
 ('jotunn.zip','ValheimModding/Jotunn/2.30.2','8aae92da2be0eb6820cd4cf57e2f6c1d6ad0d738d4915966e7c3d7a94e9a9b0f','Jotunn'),
 ('nps-1.6.0.zip','MidnightMods/NetworkPerformanceSystem/1.6.0','807b1c8546c8fac9c3d58360be628191dfd2bb3efcbc7bfcbbe62983623a08cc','NetworkPerformanceSystem')]
for archive, slug, digest, plugin in packages:
    path = fetch(archive,'https://thunderstore.io/package/download/'+slug+'/',digest)
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            normalized = name.replace('\\','/')
            if normalized == 'plugins/'+plugin+'.dll':
                target = out/'BepInEx/plugins'/plugin/(plugin+'.dll')
                target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(z.read(name))
        docs = out/'licenses'/plugin; docs.mkdir(parents=True,exist_ok=True)
        for name in ['manifest.json','README.md','CHANGELOG.md']: (docs/name).write_bytes(z.read(name))
for name,url,digest in [
 ('Jotunn-LICENSE.txt','https://raw.githubusercontent.com/Valheim-Modding/Jotunn/v2.30.2/LICENSE','72de5972d4158c4be074b5b3fffd6b42a71c7c275bfe81953c15cc85c2b89651'),
 ('NPS-LICENSE.txt','https://raw.githubusercontent.com/MidnightsFX/Valheim-Network-Performance-System/v1.6.0/LICENSE','3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986'),
 ('NPS-source-v1.6.0.tar.gz','https://api.github.com/repos/MidnightsFX/Valheim-Network-Performance-System/tarball/v1.6.0','5083e671689ea5dd90f9c00fc3e7c0dfe6dff500a3ba59ea26043063a8ace69a')]:
    (out/name).write_bytes(fetch(name,url,digest).read_bytes())
sources = out/'SOURCES.txt'; text = sources.read_text()
for line in ['Jotunn 2.30.2 (MIT): https://github.com/Valheim-Modding/Jotunn/tree/v2.30.2',
             'NetworkPerformanceSystem 1.6.0 (GPL-3.0): https://github.com/MidnightsFX/Valheim-Network-Performance-System/tree/v1.6.0; corresponding source included in NPS-source-v1.6.0.tar.gz']:
    if line not in text: text += line+'\n'
sources.write_text(text)
# Keep displayed versions with the exact package copied into each server runtime.
(out/'mod-versions.json').write_text(json.dumps({'BepInEx':'5.4.23.5','Jötunn':'2.30.2','Manager RCON':'1.1.0','NetworkPerformanceSystem':'1.6.0'},indent=2))
manifest = {'version':'1.2.0','files':{str(p.relative_to(out)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(out.rglob('*')) if p.is_file() and p.name!='manifest.json'}}
# Include dependency metadata files too; only the root manifest excludes itself.
for p in out.rglob('manifest.json'):
    if p != out/'manifest.json': manifest['files'][str(p.relative_to(out))] = hashlib.sha256(p.read_bytes()).hexdigest()
(out/'manifest.json').write_text(json.dumps(manifest,indent=2))
