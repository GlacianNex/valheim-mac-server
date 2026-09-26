#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${GAME_MANAGED_PATH:?Set GAME_MANAGED_PATH to the native server Data/Managed folder}"
dotnet="${DOTNET:-dotnet}"
cache=".build/management-source"
source_commit=105b4f06d16b23d221cde22062e48d3c0fb9a9dd
mkdir -p "$cache"
if [[ ! -d "$cache/BepInEx/.git" ]]; then
  git clone --no-checkout https://github.com/bbauti/BepInEx.git "$cache/BepInEx"
fi
git -C "$cache/BepInEx" checkout --detach "$source_commit"
git -C "$cache/BepInEx" submodule update --init --recursive
"$dotnet" publish "$cache/BepInEx/BepInEx.Preloader/BepInEx.Preloader.csproj" -c Release -o "$PWD/$cache/core"
"$dotnet" build Companion/ManagerRcon.csproj -c Release -p:LoaderPath="$PWD/$cache/core" -p:GameManagedPath="$GAME_MANAGED_PATH"
curl --fail --location --proto '=https' --tlsv1.2 https://github.com/NeighTools/UnityDoorstop/releases/download/v4.5.0/doorstop_macos_release_4.5.0.zip -o "$cache/doorstop.zip"
echo "f53e0906b60fdcaab1ed0259420863d0e9183285d2358e2edd9939a47f8c61e8  $cache/doorstop.zip" | shasum -a 256 -c -
curl --fail --location --proto '=https' --tlsv1.2 https://api.github.com/repos/NeighTools/UnityDoorstop/tarball/v4.5.0 -o "$cache/doorstop-source.tar.gz"
python3 - "$cache" <<'PY'
import sys,json,hashlib,shutil,zipfile
from pathlib import Path
cache=Path(sys.argv[1]);out=Path('dist/Management')
if out.exists(): shutil.rmtree(out)
out.mkdir(parents=True)
for p in (cache/'core').glob('*.dll'):
 target=out/'BepInEx/core'/p.name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
p=out/'BepInEx/plugins/ManagerRcon/ManagerRcon.dll';p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2('Companion/bin/Release/netstandard2.1/ManagerRcon.dll',p)
with zipfile.ZipFile(cache/'doorstop.zip') as z:(out/'libdoorstop.dylib').write_bytes(z.read('universal/libdoorstop.dylib'))
p=out/'BepInEx/config/BepInEx.cfg';p.parent.mkdir(parents=True,exist_ok=True);p.write_text('[Preloader.Entrypoint]\nAssembly = UnityEngine.CoreModule.dll\nType = GameObject\nMethod = .cctor\n[Logging.Disk]\nEnabled = true\n')
shutil.copy2(cache/'BepInEx/LICENSE',out/'BepInEx-LICENSE.txt')
shutil.copytree('Companion/licenses',out/'licenses')
shutil.copy2(cache/'doorstop-source.tar.gz',out/'UnityDoorstop-source-v4.5.0.tar.gz')
(out/'SOURCES.txt').write_text('BepInEx: https://github.com/bbauti/BepInEx/commit/105b4f06d16b23d221cde22062e48d3c0fb9a9dd\nUnityDoorstop: https://github.com/NeighTools/UnityDoorstop/releases/tag/v4.5.0\nManagerRcon: Companion/ in this manager source repository, MIT\n')
files={str(p.relative_to(out)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(out.rglob('*')) if p.is_file() and p.name!='manifest.json'}
(out/'manifest.json').write_text(json.dumps({'version':'1.1.0','files':files},indent=2))
PY
