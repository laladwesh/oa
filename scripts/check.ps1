# CCD OA environment check (Windows)
# Read-only scan by default. Only touches the machine if the candidate
# explicitly opts into the fix-it prompt below (defaults to No).
$ReportUrl = if ($env:OA_REPORT_URL) { $env:OA_REPORT_URL } else { "__REPORT_URL__" }

$processLabels = @{
  "teamviewer"       = "TeamViewer"
  "anydesk"          = "AnyDesk"
  "remoting_host"    = "Chrome Remote Desktop"
  "splashtop"        = "Splashtop"
  "rustdesk"         = "RustDesk"
  "parsec"           = "Parsec"
  "logmein"          = "LogMeIn"
  "g2comm"           = "GoToMyPC"
  "g2svc"            = "GoToMyPC"
  "zaservice"        = "Zoho Assist"
  "vncserver"        = "VNC"
  "winvnc"           = "VNC"
  "tvnserver"        = "TightVNC"
  "ultravnc"         = "UltraVNC"
  "vncviewer"        = "VNC"
  "mstsc"            = "Remote Desktop Connection (client)"
  "quickassist"      = "Microsoft Quick Assist"
  "zoom"             = "Zoom"
  "teams"            = "Microsoft Teams"
  "webexmta"         = "Webex"
  "atmgr"            = "Webex"
  "skype"            = "Skype"
  "discord"          = "Discord"
  "slack"            = "Slack"
}

$appLabels = @{
  "teamviewer"                = "TeamViewer"
  "anydesk"                   = "AnyDesk"
  "splashtop"                 = "Splashtop"
  "rustdesk"                  = "RustDesk"
  "parsec"                    = "Parsec"
  "logmein"                   = "LogMeIn"
  "gotomypc"                  = "GoToMyPC"
  "zoho assist"               = "Zoho Assist"
  "realvnc"                   = "RealVNC"
  "tightvnc"                  = "TightVNC"
  "ultravnc"                  = "UltraVNC"
  "microsoft remote desktop"  = "Microsoft Remote Desktop"
  "zoom"                      = "Zoom"
  "microsoft teams"           = "Microsoft Teams"
  "webex"                     = "Webex"
  "skype"                     = "Skype"
  "discord"                   = "Discord"
  "slack"                     = "Slack"
}

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
        $fixable[$label] = @{ kind = "process"; names = @($matches | Select-Object -ExpandProperty ProcessName -Unique) }
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
          foreach ($name in $fix.names) {
            try { Stop-Process -Name $name -Force -ErrorAction Stop } catch {}
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
