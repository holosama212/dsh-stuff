param(
  [ValidateSet('Before', 'After')][string]$Phase = 'After',
  [int]$DelaySeconds = 8
)
# Owner's rule (2026-10-29): the DSH process guard has a bug, so it is only
# used as the thing that brings DSH back during a restart.
#   Before -> turn the guard ON (clear guard-off, start the scheduled task)
#             and arm the delayed kill/relaunch.
#   After  -> turn the guard OFF again (create guard-off, stop the task).
$log = 'C:\Users\USER\dsh-plugins\guard-restart.log'
function L($m) {
  $line = (Get-Date -Format o) + '  [' + $Phase + '] ' + $m
  Add-Content -LiteralPath $log -Value $line -Encoding UTF8
  Write-Output $line
}
$off = 'C:\Users\USER\dsh-plugins\guard-off'
$task = 'DSH Guard'

if ($Phase -eq 'Before') {
  if (Test-Path $off) { Remove-Item -LiteralPath $off -Force; L 'guard-off removed' }
  try { Start-ScheduledTask -TaskName $task; L 'task started' } catch { L ('task start fail: ' + $_.Exception.Message) }
  Start-Sleep -Seconds 2
  $st = (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue).State
  L ('task state: ' + $st)
  Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\Users\USER\dsh-plugins\restart-dsh.ps1' -WindowStyle Hidden
  L ('relaunch armed, delay ' + $DelaySeconds + 's (restart-dsh.ps1 sleeps 10s itself)')
  $map = 'C:\Users\USER\AppData\Roaming\dsh-desktop\harness\media\onebot\chat-sessions.json'
  $snap = 'C:\Users\USER\AppData\Roaming\dsh-desktop\harness\media\onebot\chat-sessions.pre-restart.json'
  try { Copy-Item -LiteralPath $map -Destination $snap -Force; L 'mapping snapshot saved' } catch { L ('mapping snapshot fail: ' + $_.Exception.Message) }
}
else {
  if (-not (Test-Path $off)) { New-Item -ItemType File -Path $off -Force | Out-Null; L 'guard-off created' }
  try { Stop-ScheduledTask -TaskName $task; L 'task stopped' } catch { L ('task stop fail: ' + $_.Exception.Message) }
  Start-Sleep -Seconds 1
  $st = (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue).State
  $procs = @(Get-Process -Name 'DSH Desktop' -ErrorAction SilentlyContinue).Count
  $listen = @(Get-NetTCPConnection -LocalPort 43129 -State Listen -ErrorAction SilentlyContinue).Count
  L ('task state: ' + $st + ' | dsh procs: ' + $procs + ' | port 43129: ' + $listen)
  # Session-continuity check: did the private chat keep its session across the restart?
  $map = 'C:\Users\USER\AppData\Roaming\dsh-desktop\harness\media\onebot\chat-sessions.json'
  $snap = 'C:\Users\USER\AppData\Roaming\dsh-desktop\harness\media\onebot\chat-sessions.pre-restart.json'
  try {
    if (Test-Path $snap) {
      $cur = Get-Content -LiteralPath $map -Raw | ConvertFrom-Json
      $old = Get-Content -LiteralPath $snap -Raw | ConvertFrom-Json
      $oldPriv = $old.'private:OWNER_QQ'
      $newPriv = $cur.'private:OWNER_QQ'
      if ($oldPriv -ne $newPriv) {
        L ('WARN private session switched: ' + $oldPriv + ' -> ' + $newPriv + ' (old id was retired; rebind cron and re-read the handoff note)')
      } else {
        L ('private session kept: ' + $newPriv)
      }
    } else { L 'no mapping snapshot; skipped continuity check' }
  } catch { L ('mapping compare fail: ' + $_.Exception.Message) }
}
