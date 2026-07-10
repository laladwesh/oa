# CCD OA environment check (Windows)
# Read-only: inspects running processes, installed apps, and the RDP setting on THIS machine only.
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

$violations = New-Object System.Collections.Generic.List[string]

$procs = @()
try {
  $procs = @(Get-Process -ErrorAction Stop | Select-Object -ExpandProperty ProcessName)
} catch {}

if ($procs.Count -eq 0) {
  $violations.Add("Could not enumerate running processes - check is inconclusive, do not treat as PASS")
} else {
  foreach ($key in $processLabels.Keys) {
    $pattern = "\b$([regex]::Escape($key))\b"
    if ($procs | Where-Object { $_.ToLower() -match $pattern }) {
      $violations.Add("$($processLabels[$key]) (process running)")
    }
  }
}

$uninstallPaths = @(
  "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
  "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
$installedNames = @()
foreach ($p in $uninstallPaths) {
  $installedNames += Get-ItemProperty $p -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DisplayName -ErrorAction SilentlyContinue
}
$installedNames = @($installedNames | Where-Object { $_ })

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
foreach ($key in $appLabels.Keys) {
  $appPattern = "\b$([regex]::Escape($key))\b"
  if ($installedNames | Where-Object { $_.ToLower() -match $appPattern }) {
    $label = "$($appLabels[$key]) (installed)"
    $runningLabel = "$($appLabels[$key]) (process running)"
    if (-not $violations.Contains($runningLabel) -and -not $violations.Contains($label)) {
      $violations.Add($label)
    }
  }
}

try {
  $rdp = Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction Stop
  if ($rdp.fDenyTSConnections -eq 0) {
    $violations.Add("Remote Desktop (RDP) is enabled on this PC")
  }
} catch {}

try {
  $ra = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' -Name fAllowToGetHelp -ErrorAction Stop
  if ($ra.fAllowToGetHelp -eq 1) {
    $violations.Add("Remote Assistance is enabled on this PC")
  }
} catch {}

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

if (-not $passed) { exit 1 }
exit 0
