#requires -Version 5.1
# Refresh BOTH the full private-chat archive (Desktop\交接-私聊存档.md) and the
# small recent-tail file (Desktop\交接-私聊-最新.md) that a new session reads to
# pick up where the last one left off. Pure ASCII on purpose (PS 5.1 encoding).
$ErrorActionPreference = 'Continue'

$Py = 'C:\Program Files\DSH Desktop\resources\office-runtime\primary-runtime\dependencies\python\python.exe'
if (-not (Test-Path -LiteralPath $Py)) {
  $c = Get-Command python -ErrorAction SilentlyContinue
  if ($c) { $Py = $c.Source } else { throw 'python not found' }
}

$full = 'C:\Users\USER\dsh-plugins\export-private-chat.py'
$tail = 'C:\Users\USER\dsh-plugins\export-private-tail.py'

& $Py $full
& $Py $tail
