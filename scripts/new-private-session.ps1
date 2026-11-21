$ErrorActionPreference = 'Stop'
$h = "C:\Users\USER\AppData\Roaming\dsh-desktop\harness"
$media = Join-Path $h "media\onebot"
$sessRoot = Join-Path $h "sessions\--C-Users-Administrator-Documents-deepseek-harness-default-workspace--"
$chatKey = 'private:OWNER_QQ'
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$bak = "C:\Users\USER\dsh-plugins\session-surgery-backup-$stamp"
New-Item -ItemType Directory -Path $bak -Force | Out-Null

foreach ($f in @("chat-sessions.json", "retired-sessions.json", "switchable-sessions.json")) {
  $src = Join-Path $media $f
  if (Test-Path $src) { Copy-Item $src (Join-Path $bak $f) -Force }
}
Copy-Item (Join-Path $h "storages\workspace.json") (Join-Path $bak "workspace.json") -Force

$node = Join-Path $h ".desktop-bin\node.cmd"
$js = Join-Path $env:TEMP ("session-surgery-private-" + $stamp + ".js")
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($js, @'
const fs = require('fs');
const path = require('path');
const media = process.argv[2];
const sessRoot = process.argv[3];
const chatKey = process.argv[4];
const h = path.resolve(media, '..', '..');
const out = [];

const mapFile = path.join(media, 'chat-sessions.json');
const map = JSON.parse(fs.readFileSync(mapFile, 'utf8'));
const oldId = map[chatKey];
out.push('chatKey=' + chatKey + '  oldId=' + oldId);
if (!oldId) { out.push('NO MAPPING - nothing to retire, aborting safely'); console.log(out.join('\n')); process.exit(0); }

out.push('mapping before: ' + JSON.stringify(map));
delete map[chatKey];
fs.writeFileSync(mapFile, JSON.stringify(map, null, 2) + '\n', 'utf8');
out.push('mapping after: ' + JSON.stringify(map));

const retFile = path.join(media, 'retired-sessions.json');
let ret = [];
try { ret = JSON.parse(fs.readFileSync(retFile, 'utf8')); } catch (e) { out.push('retired read failed: ' + e.message); }
if (!Array.isArray(ret)) ret = [];
if (!ret.includes(oldId)) ret.push(oldId);
fs.writeFileSync(retFile, JSON.stringify(ret, null, 2) + '\n', 'utf8');
out.push('retired entries: ' + ret.length);

const wsFile = path.join(h, 'storages', 'workspace.json');
try {
  const j = JSON.parse(fs.readFileSync(wsFile, 'utf8'));
  let hits = 0;
  const walk = (o) => {
    if (!o || typeof o !== 'object') return;
    if (Array.isArray(o)) {
      for (let i = o.length - 1; i >= 0; i--) { if (o[i] === oldId) { o.splice(i, 1); hits++; } else walk(o[i]); }
      return;
    }
    for (const k of Object.keys(o)) { if (o[k] === oldId) { delete o[k]; hits++; } else walk(o[k]); }
  };
  walk(j);
  fs.writeFileSync(wsFile, JSON.stringify(j), 'utf8');
  out.push('workspace.json pruned refs: ' + hits);
} catch (e) { out.push('workspace.json skip: ' + e.message); }

const pcDir = path.join(h, 'storages', 'session_projcache', 'sessions');
if (fs.existsSync(pcDir)) {
  for (const f of fs.readdirSync(pcDir)) {
    if (f.startsWith(oldId)) {
      try { fs.unlinkSync(path.join(pcDir, f)); out.push('projcache removed: ' + f); }
      catch (e) { out.push('projcache rm fail ' + f + ': ' + e.message); }
    }
  }
}

const src = path.join(sessRoot, oldId);
if (fs.existsSync(src)) {
  const dstBase = path.join(h, 'sessions-retired-quarantine');
  fs.mkdirSync(dstBase, { recursive: true });
  const dst = path.join(dstBase, oldId + '--' + new Date().toISOString().replace(/[:.]/g, '-'));
  try { fs.renameSync(src, dst); out.push('QUARANTINED ' + src + ' -> ' + dst); }
  catch (e) { out.push('RENAME FAILED (' + e.code + ') ' + e.message); }
} else {
  out.push('log dir already absent');
}

console.log(out.join('\n'));
'@, $enc)

& $node $js $media $sessRoot $chatKey
"exit=$LASTEXITCODE"
"backup=$bak"
"=== chat-sessions.json after ==="
Get-Content (Join-Path $media "chat-sessions.json") -Raw
