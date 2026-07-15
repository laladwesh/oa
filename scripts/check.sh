#!/usr/bin/env bash
# CCD OA environment check (macOS / Linux)
# Read-only scan by default. Only touches the machine if the candidate
# explicitly opts into the fix-it prompt below (defaults to No).
# Uses plain indexed arrays throughout (no `declare -A`) so this also runs
# on macOS's stock /bin/bash 3.2, which has no associative-array support.
set -u

REPORT_URL="${OA_REPORT_URL:-__REPORT_URL__}"
OS_NAME="$(uname -s)"

RED_BG=$'\033[1;97;41m'
RESET=$'\033[0m'

_send_report() {
  if command -v curl >/dev/null 2>&1; then
    BODY=$(printf '{"platform":"%s","passed":false}' "$1")
    curl -s -m 5 -X POST -H "Content-Type: application/json" -d "$BODY" "$REPORT_URL" >/dev/null 2>&1 || true
  fi
}

# Hard environment check: this script only means anything on real macOS or
# native Linux. WSL (Windows Subsystem for Linux) runs bash just fine but is
# sandboxed away from the real Windows host's processes - a candidate running
# this inside WSL on Windows would get a false PASS while actual
# remote-access tools running natively on Windows stay completely invisible.
# Same idea for MSYS/Cygwin/Git-Bash-on-Windows (uname reports MINGW*/CYGWIN*).
_is_wsl=false
if [ -f /proc/version ] && grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
  _is_wsl=true
fi
[ -n "${WSL_DISTRO_NAME:-}" ] && _is_wsl=true
[ -n "${WSL_INTEROP:-}" ] && _is_wsl=true

case "$OS_NAME" in
  Darwin|Linux) ;;
  *)
    echo ""
    echo "  CCD OA ENVIRONMENT CHECK"
    echo ""
    echo "${RED_BG}    WRONG ENVIRONMENT - THIS RESULT DOES NOT COUNT          ${RESET}"
    echo ""
    echo "This is the Mac/Linux check, but it detected '$OS_NAME', which is a"
    echo "Windows-hosted shell (Git Bash/MSYS/Cygwin), not real macOS or Linux."
    echo "It cannot see your actual Windows processes. Run the PowerShell"
    echo "command your invigilator gave you instead."
    _send_report "$OS_NAME (wrong-environment)"
    exit 1
    ;;
esac

if [ "$_is_wsl" = true ]; then
  echo ""
  echo "  CCD OA ENVIRONMENT CHECK"
  echo ""
  echo "${RED_BG}    WRONG ENVIRONMENT - THIS RESULT DOES NOT COUNT          ${RESET}"
  echo ""
  echo "This looks like WSL (Windows Subsystem for Linux). WSL cannot see your"
  echo "real Windows processes, so a check run here is meaningless even if it"
  echo "shows PASS. Run the PowerShell command your invigilator gave you"
  echo "instead (irm ... | iex), not this one."
  _send_report "WSL (wrong-environment)"
  exit 1
fi

# The actual list of checked apps isn't kept as plain text in this file -
# base64-encoded below, decoded at runtime. This does not stop someone who
# deliberately decodes it (`base64 -d`), only casual reading of a curl'd file.
_PP_B64="dGVhbXZpZXdlcjpUZWFtVmlld2VyCmFueWRlc2s6QW55RGVzawpyZW1vdGluZ19ob3N0OkNocm9tZSBSZW1vdGUgRGVza3RvcApzcGxhc2h0b3A6U3BsYXNodG9wCnJ1c3RkZXNrOlJ1c3REZXNrCnBhcnNlYzpQYXJzZWMKbG9nbWVpbjpMb2dNZUluCmdvdG9teXBjOkdvVG9NeVBDCmcyY29tbTpHb1RvTXlQQwp6b2hvYXNzaXN0OlpvaG8gQXNzaXN0CnZuY3NlcnZlcjpWTkMKdm5jdmlld2VyOlZOQwp3aW52bmM6Vk5DCnRpZ2h0dm5jOlRpZ2h0Vk5DCnVsdHJhdm5jOlVsdHJhVk5DCnJlYWx2bmM6UmVhbFZOQwphcmRhZ2VudDpBcHBsZSBSZW1vdGUgRGVza3RvcApzY3JlZW5zaGFyaW5nZDptYWNPUyBTY3JlZW4gU2hhcmluZyAoYWN0aXZlKQpzc2hkOlJlbW90ZSBMb2dpbiAvIFNTSAptaWNyb3NvZnQgcmVtb3RlIGRlc2t0b3A6TWljcm9zb2Z0IFJlbW90ZSBEZXNrdG9wCnpvb20udXM6Wm9vbQp6b29tY3B0c3ZjOlpvb20KdGVhbXM6TWljcm9zb2Z0IFRlYW1zCndlYmV4OldlYmV4CnB0cmVjb3JkZXI6V2ViZXgKc2t5cGU6U2t5cGUKZGlzY29yZDpEaXNjb3JkCnNsYWNrOlNsYWNrCnF1aWNrdGltZSBwbGF5ZXI6UXVpY2tUaW1lIFBsYXllciAoc2NyZWVuIHJlY29yZGluZykK"
_AL_B64="dGVhbXZpZXdlcjpUZWFtVmlld2VyCmFueWRlc2s6QW55RGVzawpzcGxhc2h0b3A6U3BsYXNodG9wCnJ1c3RkZXNrOlJ1c3REZXNrCnBhcnNlYzpQYXJzZWMKbG9nbWVpbjpMb2dNZUluCmdvdG9teXBjOkdvVG9NeVBDCnpvaG8gYXNzaXN0OlpvaG8gQXNzaXN0CnJlYWx2bmM6UmVhbFZOQwp0aWdodHZuYzpUaWdodFZOQwp1bHRyYXZuYzpVbHRyYVZOQwptaWNyb3NvZnQgcmVtb3RlIGRlc2t0b3A6TWljcm9zb2Z0IFJlbW90ZSBEZXNrdG9wCnpvb206Wm9vbQptaWNyb3NvZnQgdGVhbXM6TWljcm9zb2Z0IFRlYW1zCndlYmV4OldlYmV4CnNreXBlOlNreXBlCmRpc2NvcmQ6RGlzY29yZApzbGFjazpTbGFjawo="

# base64 -d is GNU (Linux); macOS/BSD base64 uses -D. Try both.
_b64decode() {
  local out
  out="$(printf '%s' "$1" | base64 -d 2>/dev/null)"
  [ -z "$out" ] && out="$(printf '%s' "$1" | base64 -D 2>/dev/null)"
  printf '%s' "$out"
}

PROCESS_PATTERNS=()
while IFS= read -r _line; do
  [ -n "$_line" ] && PROCESS_PATTERNS+=("$_line")
done <<EOF
$(_b64decode "$_PP_B64")
EOF

APP_LABELS=()
while IFS= read -r _line; do
  [ -n "$_line" ] && APP_LABELS+=("$_line")
done <<EOF
$(_b64decode "$_AL_B64")
EOF

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
  PS_OUT_LOWER="$(echo "$PS_OUT" | grep -vi '/system/library/' | tr '[:upper:]' '[:lower:]')"

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

    if command -v launchctl >/dev/null 2>&1; then
      _ss_state="$(launchctl print system/com.apple.screensharing 2>/dev/null)"
      if echo "$_ss_state" | grep -qE "state = (running|waiting)"; then
        VIOLATIONS+=("macOS Screen Sharing is enabled in System Settings")
      fi
      # Remote Login (SSH) is also socket-activated on macOS - the sshd
      # process check above only catches an active connection, same gap as
      # Screen Sharing had. Check whether it's enabled at all, not just
      # mid-session right now.
      _ssh_state="$(launchctl print system/com.openssh.sshd 2>/dev/null)"
      if echo "$_ssh_state" | grep -qE "state = (running|waiting)"; then
        already_ssh=0
        if [ "${#VIOLATIONS[@]}" -gt 0 ]; then
          for v in "${VIOLATIONS[@]}"; do
            [ "$v" = "Remote Login / SSH (process running)" ] && already_ssh=1
          done
        fi
        [ "$already_ssh" -eq 0 ] && VIOLATIONS+=("Remote Login / SSH is enabled in System Settings")
      fi
    fi
  fi

  PASSED=true
  [ "${#VIOLATIONS[@]}" -gt 0 ] && PASSED=false
}

GREEN_BG=$'\033[1;97;42m'
YELLOW=$'\033[1;33m'
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

# Many remote-access tools install a macOS LaunchAgent/LaunchDaemon that
# auto-relaunches the app the instant it's killed - that's specifically why
# they behave that way, so the remote session survives a manual force-quit.
# A plain `pkill` alone won't stick; the watchdog has to be disabled first
# or the process just comes back.
disable_launch_items() {
  local pattern="$1"
  local dir domain plist base
  for dir_domain in "$HOME/Library/LaunchAgents:user" "/Library/LaunchAgents:system" "/Library/LaunchDaemons:system"; do
    dir="${dir_domain%%:*}"
    domain="${dir_domain#*:}"
    [ -d "$dir" ] || continue
    for plist in "$dir"/*.plist; do
      [ -e "$plist" ] || continue
      base="$(basename "$plist" | tr '[:upper:]' '[:lower:]')"
      if echo "$base" | grep -qiw "$pattern"; then
        echo "  Also disabling auto-restart watchdog: $(basename "$plist")"
        if [ "$domain" = "system" ]; then
          sudo launchctl unload -w "$plist" 2>/dev/null || true
          sudo mv "$plist" "$plist.disabled" 2>/dev/null || true
        else
          launchctl unload -w "$plist" 2>/dev/null || true
          mv "$plist" "$plist.disabled" 2>/dev/null || true
        fi
      fi
    done
  done
}

if [ "$PASSED" = false ] && [ -r /dev/tty ] && { [ "${#FIXABLE_PROC_PATTERNS[@]}" -gt 0 ] || [ "${#FIXABLE_APP_NAMES[@]}" -gt 0 ]; }; then
  echo "${YELLOW}Fixable automatically: force-quitting the apps above (save your work first),"
  echo "disabling any auto-restart watchdog (may prompt for your Mac password for"
  echo "system-level ones), and moving installed-but-not-running apps to Trash"
  echo "(recoverable). Nothing else on this Mac/Linux machine is touched.${RESET}"
  read -p "Attempt to fix these automatically now? [y/N] " -r choice < /dev/tty || choice=""
  if [[ "$choice" =~ ^[Yy] ]]; then
    for pattern in "${FIXABLE_PROC_PATTERNS[@]:-}"; do
      [ -z "$pattern" ] && continue
      echo "Fixing: closing process matching '$pattern'"
      if [ "$OS_NAME" = "Darwin" ]; then
        disable_launch_items "$pattern"
      fi
      # Some apps relaunch themselves within a second or two via a
      # helper/updater/tray process even with no LaunchAgent involved. A
      # single kill can lose that race, so kill-and-recheck a few times
      # instead of trusting one shot.
      attempt=0
      while [ "$attempt" -lt 4 ]; do
        pkill -9 -i -f "$pattern" 2>/dev/null || true
        sleep 1
        still_running=""
        new_ps="$(ps -axo comm= 2>/dev/null)"
        [ -z "$new_ps" ] && new_ps="$(ps -eo comm= 2>/dev/null)"
        echo "$new_ps" | grep -vi '/system/library/' | grep -qiw "$pattern" && still_running=1
        [ -z "$still_running" ] && break
        attempt=$((attempt + 1))
      done
      [ -n "$still_running" ] && echo "  Still running after repeated attempts - may need manual quit or Administrator/root privileges."
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
echo "AirPlay/Screen Mirroring, Sidecar, Universal Control, and browser-based"
echo "tools (Google Meet, Whereby, etc.) cannot be reliably checked from the"
echo "command line and are NOT covered by this automated check."
echo ""

# Anonymous aggregate ping only: platform + pass/fail. No violation details,
# no identity, no files are ever sent.
if command -v curl >/dev/null 2>&1; then
  BODY=$(printf '{"platform":"%s","passed":%s}' "$OS_NAME" "$PASSED")
  curl -s -m 5 -X POST -H "Content-Type: application/json" -d "$BODY" "$REPORT_URL" >/dev/null 2>&1 || true
fi

# Keep the window open so the invigilator has time to read the banner,
# instead of it vanishing the instant the script finishes (e.g. when
# launched via a double-clickable script or a Terminal profile that closes
# on exit). Skipped if there's no real interactive terminal attached, so
# this never hangs a non-interactive run.
if [ -r /dev/tty ]; then
  read -p "Press Enter to close this window... " -r _ < /dev/tty || true
fi

[ "$PASSED" = false ] && exit 1
exit 0
