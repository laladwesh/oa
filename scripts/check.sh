#!/usr/bin/env bash
# CCD OA environment check (macOS / Linux)
# Read-only scan by default. Only touches the machine if the candidate
# explicitly opts into the fix-it prompt below (defaults to No).
# Uses plain indexed arrays throughout (no `declare -A`) so this also runs
# on macOS's stock /bin/bash 3.2, which has no associative-array support.
set -u

REPORT_URL="${OA_REPORT_URL:-__REPORT_URL__}"
OS_NAME="$(uname -s)"

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

APP_LABELS=(
  "teamviewer:TeamViewer"
  "anydesk:AnyDesk"
  "splashtop:Splashtop"
  "rustdesk:RustDesk"
  "parsec:Parsec"
  "logmein:LogMeIn"
  "gotomypc:GoToMyPC"
  "zoho assist:Zoho Assist"
  "realvnc:RealVNC"
  "tightvnc:TightVNC"
  "ultravnc:UltraVNC"
  "microsoft remote desktop:Microsoft Remote Desktop"
  "zoom:Zoom"
  "microsoft teams:Microsoft Teams"
  "webex:Webex"
  "skype:Skype"
  "discord:Discord"
  "slack:Slack"
  "quicktime player:QuickTime Player (screen recording)"
)

# Populates the global VIOLATIONS array. FIXABLE_PROC_PATTERNS collects the
# raw process-name patterns worth killing; FIXABLE_APP_NAMES collects the
# actual /Applications folder names worth trashing (real case, not the
# lowercased match key).
scan() {
  VIOLATIONS=()
  FIXABLE_PROC_PATTERNS=()
  FIXABLE_APP_NAMES=()

  PS_OUT="$(ps -axo comm= 2>/dev/null)"
  [ -z "$PS_OUT" ] && PS_OUT="$(ps -eo comm= 2>/dev/null)"
  PS_OUT_LOWER="$(echo "$PS_OUT" | tr '[:upper:]' '[:lower:]')"

  if [ -z "$PS_OUT" ]; then
    VIOLATIONS+=("Could not enumerate running processes - check is inconclusive, do not treat as PASS")
  else
    for entry in "${PROCESS_PATTERNS[@]}"; do
      pattern="${entry%%:*}"
      label="${entry#*:}"
      if echo "$PS_OUT_LOWER" | grep -qiw "$pattern"; then
        VIOLATIONS+=("$label (process running)")
        FIXABLE_PROC_PATTERNS+=("$pattern")
      fi
    done
  fi

  if [ "$OS_NAME" = "Darwin" ]; then
    APP_LISTING="$(ls /Applications 2>/dev/null)"
    APP_NAMES_LOWER="$(echo "$APP_LISTING" | tr '[:upper:]' '[:lower:]')"
    for entry in "${APP_LABELS[@]}"; do
      key="${entry%%:*}"
      label="${entry#*:} (installed)"
      running_label="${entry#*:} (process running)"
      if echo "$APP_NAMES_LOWER" | grep -qiw "$key"; then
        already=0
        if [ "${#VIOLATIONS[@]}" -gt 0 ]; then
          for v in "${VIOLATIONS[@]}"; do
            [ "$v" = "$running_label" ] && already=1
          done
        fi
        if [ "$already" -eq 0 ]; then
          VIOLATIONS+=("$label")
          match="$(echo "$APP_LISTING" | grep -iw "$key" | head -1)"
          [ -n "$match" ] && FIXABLE_APP_NAMES+=("$match")
        fi
      fi
    done
  fi

  PASSED=true
  [ "${#VIOLATIONS[@]}" -gt 0 ] && PASSED=false
}

GREEN_BG=$'\033[1;97;42m'
RED_BG=$'\033[1;97;41m'
YELLOW=$'\033[1;33m'
RESET=$'\033[0m'
BOLD=$'\033[1m'

print_banner() {
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
}

scan
print_banner

if [ "$PASSED" = false ] && [ -r /dev/tty ] && { [ "${#FIXABLE_PROC_PATTERNS[@]}" -gt 0 ] || [ "${#FIXABLE_APP_NAMES[@]}" -gt 0 ]; }; then
  echo "${YELLOW}Fixable automatically: force-quitting the apps above (save your work first)"
  echo "and moving installed-but-not-running apps to Trash (recoverable). Nothing"
  echo "else on this Mac/Linux machine is touched.${RESET}"
  read -p "Attempt to fix these automatically now? [y/N] " -r choice < /dev/tty || choice=""
  if [[ "$choice" =~ ^[Yy] ]]; then
    for pattern in "${FIXABLE_PROC_PATTERNS[@]:-}"; do
      [ -z "$pattern" ] && continue
      echo "Fixing: closing process matching '$pattern'"
      pkill -9 -i -f "$pattern" 2>/dev/null || true
    done
    if [ "$OS_NAME" = "Darwin" ]; then
      for appname in "${FIXABLE_APP_NAMES[@]:-}"; do
        [ -z "$appname" ] && continue
        echo "Fixing: moving '$appname' to Trash"
        osascript -e "tell application \"Finder\" to delete POSIX file \"/Applications/$appname\"" >/dev/null 2>&1 || \
          echo "  Could not move '$appname' to Trash automatically - remove it manually."
      done
    fi
    echo ""
    echo "Re-scanning..."
    scan
    print_banner
  fi
fi

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
