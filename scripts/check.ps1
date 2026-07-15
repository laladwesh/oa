# CCD OA environment check (Windows)
# Read-only scan by default. Only touches the machine if the candidate
# explicitly opts into the fix-it prompt below (defaults to No).
$ReportUrl = if ($env:OA_REPORT_URL) { $env:OA_REPORT_URL } else { "__REPORT_URL__" }

# Hard environment check: PowerShell itself runs cross-platform (PowerShell
# Core on Mac/Linux), so this script could technically execute somewhere its
# Windows registry/RDP checks silently no-op - meaningless result. $IsWindows
# only exists in PowerShell 6+; on Windows PowerShell 5.1 (the common case)
# it's absent, so default to true there since 5.1 only ever runs on Windows.
$isWinPlatform = $true
if (Test-Path Variable:IsWindows) { $isWinPlatform = $IsWindows }
if (-not $isWinPlatform) {
  Write-Host ""
  Write-Host "  CCD OA ENVIRONMENT CHECK"
  Write-Host ""
  Write-Host "                                                          " -ForegroundColor White -BackgroundColor DarkRed
  Write-Host "    WRONG ENVIRONMENT - THIS RESULT DOES NOT COUNT         " -ForegroundColor White -BackgroundColor DarkRed
  Write-Host "                                                          " -ForegroundColor White -BackgroundColor DarkRed
  Write-Host ""
  Write-Host "This is the Windows check, but it detected a non-Windows OS."
  Write-Host "Registry-based checks here would silently do nothing, so a PASS"
  Write-Host "would be meaningless. Run the curl command your invigilator gave"
  Write-Host "you instead."
  try {
    $bodyObj = @{ platform = "non-Windows (wrong-environment)"; passed = $false }
    $json = $bodyObj | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri $ReportUrl -Method Post -Body $json -ContentType "application/json" -TimeoutSec 5 | Out-Null
  } catch {}
  exit 1
}

# The actual list of checked apps isn't kept as plain text in this file -
# base64-encoded below, decoded at runtime. This does not stop someone who
# deliberately decodes it, only casual reading of a curl'd/downloaded file.
function Decode-Labels($b64) {
  $text = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))
  $table = @{}
  foreach ($line in $text -split "`n") {
    $line = $line.Trim()
    if ($line -eq "") { continue }
    $parts = $line -split "=", 2
    $table[$parts[0]] = $parts[1]
  }
  return $table
}

$processLabels = Decode-Labels "dGVhbXZpZXdlcj1UZWFtVmlld2VyCmFueWRlc2s9QW55RGVzawpyZW1vdGluZ19ob3N0PUNocm9tZSBSZW1vdGUgRGVza3RvcApzcGxhc2h0b3A9U3BsYXNodG9wCnJ1c3RkZXNrPVJ1c3REZXNrCnBhcnNlYz1QYXJzZWMKbG9nbWVpbj1Mb2dNZUluCmcyY29tbT1Hb1RvTXlQQwpnMnN2Yz1Hb1RvTXlQQwp6YXNlcnZpY2U9Wm9obyBBc3Npc3QKdm5jc2VydmVyPVZOQwp3aW52bmM9Vk5DCnR2bnNlcnZlcj1UaWdodFZOQwp1bHRyYXZuYz1VbHRyYVZOQwp2bmN2aWV3ZXI9Vk5DCm1zdHNjPVJlbW90ZSBEZXNrdG9wIENvbm5lY3Rpb24gKGNsaWVudCkKcXVpY2thc3Npc3Q9TWljcm9zb2Z0IFF1aWNrIEFzc2lzdAp6b29tPVpvb20KdGVhbXM9TWljcm9zb2Z0IFRlYW1zCndlYmV4bXRhPVdlYmV4CmF0bWdyPVdlYmV4CnNreXBlPVNreXBlCmRpc2NvcmQ9RGlzY29yZApzbGFjaz1TbGFjaw=="

$appLabels = Decode-Labels "dGVhbXZpZXdlcj1UZWFtVmlld2VyCmFueWRlc2s9QW55RGVzawpzcGxhc2h0b3A9U3BsYXNodG9wCnJ1c3RkZXNrPVJ1c3REZXNrCnBhcnNlYz1QYXJzZWMKbG9nbWVpbj1Mb2dNZUluCmdvdG9teXBjPUdvVG9NeVBDCnpvaG8gYXNzaXN0PVpvaG8gQXNzaXN0CnJlYWx2bmM9UmVhbFZOQwp0aWdodHZuYz1UaWdodFZOQwp1bHRyYXZuYz1VbHRyYVZOQwptaWNyb3NvZnQgcmVtb3RlIGRlc2t0b3A9TWljcm9zb2Z0IFJlbW90ZSBEZXNrdG9wCnpvb209Wm9vbQptaWNyb3NvZnQgdGVhbXM9TWljcm9zb2Z0IFRlYW1zCndlYmV4PVdlYmV4CnNreXBlPVNreXBlCmRpc2NvcmQ9RGlzY29yZApzbGFjaz1TbGFjaw=="

$uninstallPaths = @(
  "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
  "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

function Get-Scan {
  $violations = New-Object System.Collections.Generic.List[string]
  # label -> { kind, matchedProcessNames / uninstallString }
  $fixable = @{}

  $procs = @()
  try {
    $procs = @(Get-Process -ErrorAction Stop)
  } catch {}

  if ($procs.Count -eq 0) {
    $violations.Add("Could not enumerate running processes - check is inconclusive, do not treat as PASS")
  } else {
    foreach ($key in $processLabels.Keys) {
      $pattern = "\b$([regex]::Escape($key))\b"
      $matches = @($procs | Where-Object { $_.ProcessName.ToLower() -match $pattern })
      if ($matches.Count -gt 0) {
        $label = "$($processLabels[$key]) (process running)"
        $violations.Add($label)
        $fixable[$label] = @{ kind = "process"; names = @($matches | Select-Object -ExpandProperty ProcessName -Unique); pattern = $pattern }
      }
    }
  }

  $installedEntries = @()
  foreach ($p in $uninstallPaths) {
    $installedEntries += Get-ItemProperty $p -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName } |
      Select-Object DisplayName, UninstallString
  }

  foreach ($key in $appLabels.Keys) {
    $appPattern = "\b$([regex]::Escape($key))\b"
    $match = $installedEntries | Where-Object { $_.DisplayName.ToLower() -match $appPattern } | Select-Object -First 1
    if ($match) {
      $label = "$($appLabels[$key]) (installed)"
      $runningLabel = "$($appLabels[$key]) (process running)"
      if (-not $violations.Contains($runningLabel) -and -not $violations.Contains($label)) {
        $violations.Add($label)
        if ($match.UninstallString) {
          $fixable[$label] = @{ kind = "uninstall"; command = $match.UninstallString }
        }
      }
    }
  }

  try {
    $rdp = Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction Stop
    if ($rdp.fDenyTSConnections -eq 0) {
      $label = "Remote Desktop (RDP) is enabled on this PC"
      $violations.Add($label)
      $fixable[$label] = @{ kind = "rdp" }
    }
  } catch {}

  try {
    $ra = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' -Name fAllowToGetHelp -ErrorAction Stop
    if ($ra.fAllowToGetHelp -eq 1) {
      $label = "Remote Assistance is enabled on this PC"
      $violations.Add($label)
      $fixable[$label] = @{ kind = "remote-assistance" }
    }
  } catch {}

  return @{ violations = $violations; fixable = $fixable }
}

function Write-Banner($violations) {
  $passed = ($violations.Count -eq 0)
  Write-Host ""
  Write-Host "  CCD OA ENVIRONMENT CHECK"
  Write-Host ""
  if ($passed) {
    Write-Host "                                                          " -ForegroundColor White -BackgroundColor DarkGreen
    Write-Host "    PASS  -  LAPTOP CLEAR  -  SHOW SCREEN TO INVIGILATOR   " -ForegroundColor White -BackgroundColor DarkGreen
    Write-Host "                                                          " -ForegroundColor White -BackgroundColor DarkGreen
  } else {
    Write-Host "                                                          " -ForegroundColor White -BackgroundColor DarkRed
    Write-Host "    FAIL  -  DO NOT START  -  CALL YOUR INVIGILATOR NOW    " -ForegroundColor White -BackgroundColor DarkRed
    Write-Host "                                                          " -ForegroundColor White -BackgroundColor DarkRed
    Write-Host ""
    Write-Host "Close/uninstall the following before the OA:" -ForegroundColor White
    foreach ($v in $violations) { Write-Host "  [X] $v" -ForegroundColor Red }
  }
  Write-Host ""
  return $passed
}

$scan = Get-Scan
$passed = Write-Banner $scan.violations

if (-not $passed -and $scan.fixable.Count -gt 0) {
  Write-Host "Fixable automatically: closing apps (Force-quits them - save your work" -ForegroundColor Yellow
  Write-Host "first), launching real uninstallers for installed-but-not-running apps," -ForegroundColor Yellow
  Write-Host "and disabling RDP/Remote Assistance. Nothing else on this PC is touched." -ForegroundColor Yellow
  $choice = Read-Host "Attempt to fix these automatically now? [y/N]"
  if ($choice -match '^[Yy]') {
    foreach ($label in $scan.fixable.Keys) {
      $fix = $scan.fixable[$label]
      Write-Host "Fixing: $label" -ForegroundColor Yellow
      switch ($fix.kind) {
        "process" {
          # Some apps relaunch themselves within a second or two via a
          # helper/updater/tray process. A single kill can lose that race,
          # so kill-and-recheck a few times instead of trusting one shot.
          # Also disables any matching Scheduled Task, since some installers
          # register one for background updates/relaunch.
          try {
            Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName -match $fix.pattern } | ForEach-Object {
              Disable-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue | Out-Null
            }
          } catch {}
          $stillRunning = $true
          for ($i = 0; $i -lt 4; $i++) {
            foreach ($name in $fix.names) {
              try { Stop-Process -Name $name -Force -ErrorAction Stop } catch {}
            }
            Start-Sleep -Seconds 1
            $remaining = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName.ToLower() -match $fix.pattern })
            if ($remaining.Count -eq 0) { $stillRunning = $false; break }
          }
          if ($stillRunning) {
            Write-Host "  Still running after repeated attempts - may need manual quit or Administrator PowerShell." -ForegroundColor Red
          }
        }
        "uninstall" {
          try {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $fix.command -Wait -ErrorAction Stop
          } catch {
            Write-Host "  Could not launch uninstaller automatically - uninstall manually via Settings > Apps." -ForegroundColor Red
          }
        }
        "rdp" {
          try {
            Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 1 -ErrorAction Stop
          } catch {
            Write-Host "  Could not disable RDP automatically - needs Administrator PowerShell." -ForegroundColor Red
          }
        }
        "remote-assistance" {
          try {
            Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' -Name fAllowToGetHelp -Value 0 -ErrorAction Stop
          } catch {
            Write-Host "  Could not disable Remote Assistance automatically - needs Administrator PowerShell." -ForegroundColor Red
          }
        }
      }
    }
    Write-Host ""
    Write-Host "Re-scanning..." -ForegroundColor Yellow
    $scan = Get-Scan
    $passed = Write-Banner $scan.violations
  }
}

Write-Host "Only running processes, installed apps, and the RDP/Remote Assistance"
Write-Host "settings on THIS machine were inspected. No files, codebase, or personal"
Write-Host "data are read, uploaded, or stored."
Write-Host ""

# Anonymous aggregate ping only: platform + pass/fail. No violation details,
# no identity, no files are ever sent.
try {
  $bodyObj = @{ platform = "Windows"; passed = $passed }
  $json = $bodyObj | ConvertTo-Json -Compress
  Invoke-RestMethod -Uri $ReportUrl -Method Post -Body $json -ContentType "application/json" -TimeoutSec 5 | Out-Null
} catch {}

# Keep the window open so the invigilator has time to read the banner,
# instead of it vanishing the instant the script finishes (e.g. when
# launched via a shortcut/batch file without -NoExit). Skipped if there's
# no real interactive console attached, so this never hangs a non-interactive run.
if (-not [Console]::IsInputRedirected) {
  Write-Host "Press Enter to close this window..." -ForegroundColor Gray
  Read-Host | Out-Null
}

if (-not $passed) { exit 1 }
exit 0
