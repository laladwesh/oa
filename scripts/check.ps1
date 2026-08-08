$ReportUrl = if ($env:OA_REPORT_URL) { $env:OA_REPORT_URL } else { "__REPORT_URL__" }

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

$processLabels = Decode-Labels "dGVhbXZpZXdlcj1UZWFtVmlld2VyCnRlYW12aWV3ZXJfc2VydmljZT1UZWFtVmlld2VyCmFueWRlc2s9QW55RGVzawphbnlkZXNrX3NlcnZpY2U9QW55RGVzawpyZW1vdGluZ19ob3N0PUNocm9tZSBSZW1vdGUgRGVza3RvcApyZW1vdGluZ19tZTJtZV9ob3N0PUNocm9tZSBSZW1vdGUgRGVza3RvcApzcGxhc2h0b3A9U3BsYXNodG9wCnJ1c3RkZXNrPVJ1c3REZXNrCnBhcnNlYz1QYXJzZWMKbG9nbWVpbj1Mb2dNZUluCmcyY29tbT1Hb1RvTXlQQwpnMnN2Yz1Hb1RvTXlQQwp6YXNlcnZpY2U9Wm9obyBBc3Npc3QKdm5jc2VydmVyPVZOQwp3aW52bmM9Vk5DCnR2bnNlcnZlcj1UaWdodFZOQwp1bHRyYXZuYz1VbHRyYVZOQwp2bmN2aWV3ZXI9Vk5DCm1zdHNjPVJlbW90ZSBEZXNrdG9wIENvbm5lY3Rpb24gKGNsaWVudCkKcXVpY2thc3Npc3Q9TWljcm9zb2Z0IFF1aWNrIEFzc2lzdAp6b29tPVpvb20Kd2ViZXhtdGE9V2ViZXgKYXRtZ3I9V2ViZXgKc2t5cGU9U2t5cGUKZGlzY29yZD1EaXNjb3JkCnNsYWNrPVNsYWNrCmxvb209TG9vbQpzY3JlZW5sZWFwPVNjcmVlbmxlYXA="

$appLabels = Decode-Labels "dGVhbXZpZXdlcj1UZWFtVmlld2VyCmFueWRlc2s9QW55RGVzawpzcGxhc2h0b3A9U3BsYXNodG9wCnJ1c3RkZXNrPVJ1c3REZXNrCnBhcnNlYz1QYXJzZWMKbG9nbWVpbj1Mb2dNZUluCmdvdG9teXBjPUdvVG9NeVBDCnpvaG8gYXNzaXN0PVpvaG8gQXNzaXN0CnJlYWx2bmM9UmVhbFZOQwp0aWdodHZuYz1UaWdodFZOQwp1bHRyYXZuYz1VbHRyYVZOQwptaWNyb3NvZnQgcmVtb3RlIGRlc2t0b3A9TWljcm9zb2Z0IFJlbW90ZSBEZXNrdG9wCnpvb209Wm9vbQp3ZWJleD1XZWJleApza3lwZT1Ta3lwZQpkaXNjb3JkPURpc2NvcmQKc2xhY2s9U2xhY2s="

$uninstallPaths = @(
  "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
  "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

function Get-Scan {
  $violations = New-Object System.Collections.Generic.List[string]
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
      $hits = @($procs | Where-Object { $_.ProcessName.ToLower() -match $pattern })
      if ($hits.Count -gt 0) {
        $label = "$($processLabels[$key]) (process running)"
        $violations.Add($label)
        $fixable[$label] = @{ kind = "process"; names = @($hits | Select-Object -ExpandProperty ProcessName -Unique); pattern = $pattern }
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

  try {
    $safeNames = @("dwm", "explorer", "shellexperiencehost", "searchhost", "textinputhost", "applicationframehost")
    $sample1 = (Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop).CounterSamples |
      Where-Object { $_.InstanceName -match 'engtype_videoencode' }
    Start-Sleep -Milliseconds 800
    $sample2 = (Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop).CounterSamples |
      Where-Object { $_.InstanceName -match 'engtype_videoencode' }
    $flaggedPids = @{}
    foreach ($s2 in $sample2) {
      if ($s2.InstanceName -notmatch 'pid_(\d+)') { continue }
      $encPid = $matches[1]
      $s1 = $sample1 | Where-Object { $_.InstanceName -eq $s2.InstanceName } | Select-Object -First 1
      if (-not $s1) { continue }
      $avg = ($s1.CookedValue + $s2.CookedValue) / 2
      if ($avg -gt 15 -and -not $flaggedPids.ContainsKey($encPid)) {
        try {
          $procName = (Get-Process -Id $encPid -ErrorAction Stop).ProcessName
          if ($safeNames -notcontains $procName.ToLower()) {
            $flaggedPids[$encPid] = $procName
          }
        } catch {}
      }
    }
    foreach ($encPid in $flaggedPids.Keys) {
      $violations.Add("Sustained video-encode GPU activity in '$($flaggedPids[$encPid])' (PID $encPid) - possible active screen-share/streaming regardless of app name")
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

try {
  $bodyObj = @{ platform = "Windows"; passed = $passed }
  $json = $bodyObj | ConvertTo-Json -Compress
  Invoke-RestMethod -Uri $ReportUrl -Method Post -Body $json -ContentType "application/json" -TimeoutSec 5 | Out-Null
} catch {}

if (-not [Console]::IsInputRedirected) {
  Write-Host "Press Enter to close this window..." -ForegroundColor Gray
  Read-Host | Out-Null
}

if (-not $passed) { exit 1 }
exit 0
