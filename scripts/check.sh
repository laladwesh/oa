#!/usr/bin/env bash
# CCD OA environment check (macOS / Linux)
# Read-only: inspects running processes and installed apps on THIS machine only.
set -u

REPORT_URL="${OA_REPORT_URL:-__REPORT_URL__}"
OS_NAME="$(uname -s)"
VIOLATIONS=()

PROCESS_PATTERNS=(
  "teamviewer:TeamViewer"
  "anydesk:AnyDesk"
  "remoting_host:Chrome Remote Desktop"
  "splashtop:Splashtop"
  "rustdesk:RustDesk"
  "parsec:Parsec"
  "logmein:LogMeIn"
  "gotomypc:GoToMyPC"
  "g2comm:GoToMyPC"
  "zohoassist:Zoho Assist"
  "vncserver:VNC"
  "vncviewer:VNC"
  "winvnc:VNC"
  "tightvnc:TightVNC"
  "ultravnc:UltraVNC"
  "realvnc:RealVNC"
  "ardagent:Apple Remote Desktop"
  "screensharingd:macOS Screen Sharing (active)"
  "sshd:Remote Login / SSH"
  "microsoft remote desktop:Microsoft Remote Desktop"
  "zoom.us:Zoom"
  "zoomcptsvc:Zoom"
  "teams:Microsoft Teams"
  "webex:Webex"
  "ptrecorder:Webex"
  "skype:Skype"
  "discord:Discord"
  "slack:Slack"
  "quicktime player:QuickTime Player (screen recording)"
)

PS_OUT="$(ps -axo comm= 2>/dev/null)"
[ -z "$PS_OUT" ] && PS_OUT="$(ps -eo comm= 2>/dev/null)"
PS_OUT_LOWER="$(echo "$PS_OUT" | tr '[:upper:]' '[:lower:]')"

# A real machine always has processes running. If we got nothing back, the
# check itself failed (unsupported ps flags, sandboxed shell, tampering,
# etc.) - fail closed instead of silently reporting a clean scan.
if [ -z "$PS_OUT" ]; then
  VIOLATIONS+=("Could not enumerate running processes - check is inconclusive, do not treat as PASS")
else
  for entry in "${PROCESS_PATTERNS[@]}"; do
    pattern="${entry%%:*}"
    label="${entry#*:}"
    if echo "$PS_OUT_LOWER" | grep -qiw "$pattern"; then
      VIOLATIONS+=("$label (process running)")
    fi
  done
fi

# Installed-but-not-running apps (macOS /Applications scan)
if [ "$OS_NAME" = "Darwin" ]; then
  APP_NAMES="$(ls /Applications 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  declare -A APP_LABELS=(
    ["teamviewer"]="TeamViewer"
    ["anydesk"]="AnyDesk"
    ["splashtop"]="Splashtop"
    ["rustdesk"]="RustDesk"
    ["parsec"]="Parsec"
    ["logmein"]="LogMeIn"
    ["gotomypc"]="GoToMyPC"
    ["zoho assist"]="Zoho Assist"
    ["realvnc"]="RealVNC"
    ["tightvnc"]="TightVNC"
    ["ultravnc"]="UltraVNC"
    ["microsoft remote desktop"]="Microsoft Remote Desktop"
    ["zoom"]="Zoom"
    ["microsoft teams"]="Microsoft Teams"
    ["webex"]="Webex"
    ["skype"]="Skype"
    ["discord"]="Discord"
    ["slack"]="Slack"
    ["quicktime player"]="QuickTime Player (screen recording)"
  )
  for key in "${!APP_LABELS[@]}"; do
    if echo "$APP_NAMES" | grep -qiw "$key"; then
      label="${APP_LABELS[$key]} (installed)"
      running_label="${APP_LABELS[$key]} (process running)"
      already=0
      if [ "${#VIOLATIONS[@]}" -gt 0 ]; then
        for v in "${VIOLATIONS[@]}"; do
          [ "$v" = "$running_label" ] && already=1
        done
      fi
      [ "$already" -eq 0 ] && VIOLATIONS+=("$label")
    fi
  done
fi

PASSED=true
[ "${#VIOLATIONS[@]}" -gt 0 ] && PASSED=false

GREEN_BG=$'\033[1;97;42m'
RED_BG=$'\033[1;97;41m'
RESET=$'\033[0m'
BOLD=$'\033[1m'

echo ""
echo "  CCD OA ENVIRONMENT CHECK"
echo ""
if [ "$PASSED" = true ]; then
  echo "${GREEN_BG}                                                          ${RESET}"
  echo "${GREEN_BG}    PASS  -  LAPTOP CLEAR  -  SHOW SCREEN TO INVIGILATOR   ${RESET}"
  echo "${GREEN_BG}                                                          ${RESET}"
else
  echo "${RED_BG}                                                          ${RESET}"
  echo "${RED_BG}    FAIL  -  DO NOT START  -  CALL YOUR INVIGILATOR NOW    ${RESET}"
  echo "${RED_BG}                                                          ${RESET}"
  echo ""
  echo "${BOLD}Close/uninstall the following before the OA:${RESET}"
  for v in "${VIOLATIONS[@]}"; do
    echo "  ${RED_BG} X ${RESET} $v"
  done
fi
echo ""
echo "Only running processes and installed apps on THIS machine were inspected."
echo "No files, codebase, or personal data are read, uploaded, or stored."
echo "AirPlay/Screen Mirroring, Sidecar, and Universal Control cannot be reliably"
echo "checked from the command line and are NOT covered by this automated check."
echo ""

# Anonymous aggregate ping only: platform + pass/fail. No violation details,
# no identity, no files are ever sent.
if command -v curl >/dev/null 2>&1; then
  BODY=$(printf '{"platform":"%s","passed":%s}' "$OS_NAME" "$PASSED")
  curl -s -m 5 -X POST -H "Content-Type: application/json" -d "$BODY" "$REPORT_URL" >/dev/null 2>&1 || true
fi

[ "$PASSED" = false ] && exit 1
exit 0
