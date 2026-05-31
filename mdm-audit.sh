#!/bin/bash
set -euo pipefail

# Read-only macOS MDM posture audit.
# This script does not modify files, services, profiles, or system settings.
# By default, output is saved to reports/mdm-audit-YYYY-mm-dd-HHMMSS.txt and printed to screen.
# A Markdown copy is also saved as reports/mdm-audit-YYYY-mm-dd-HHMMSS.md.
# Terminal output may use color; saved reports are plain text without ANSI color codes.

COLLECT_LOGS=false
for arg in "$@"; do
  case "$arg" in
    --collect-logs) COLLECT_LOGS=true ;;
    -h|--help)
      cat <<'EOF'
Usage: ./mdm-audit.sh [--collect-logs]

Options:
  --collect-logs   Save recent read-only MDM-related unified logs next to the report
  -h, --help       Show this help

Outputs:
  reports/mdm-audit-YYYY-mm-dd-HHMMSS.txt   Plain-text report without color codes
  reports/mdm-audit-YYYY-mm-dd-HHMMSS.md    Markdown report for submission
EOF
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$arg" >&2
      printf 'Run ./mdm-audit.sh --help for usage.\n' >&2
      exit 2
      ;;
  esac
done

if [[ "${MDM_AUDIT_LOGGING:-}" != "1" ]]; then
  SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  REPORT_DIR="${REPORT_DIR:-${SCRIPT_DIR}/reports}"
  mkdir -p "$REPORT_DIR"
  REPORT_FILE="${REPORT_FILE:-${REPORT_DIR}/mdm-audit-$(date +%Y-%m-%d-%H%M%S).txt}"
  MARKDOWN_FILE="${REPORT_FILE%.txt}.md"
  TMP_REPORT="${REPORT_FILE}.ansi.tmp"
  export MDM_AUDIT_LOGGING=1 REPORT_FILE

  "$0" "$@" 2>&1 | tee "$TMP_REPORT"
  run_status=${PIPESTATUS[0]}

  if command -v perl >/dev/null 2>&1; then
    perl -pe 's/\e\[[0-9;]*m//g' "$TMP_REPORT" >"$REPORT_FILE"
  else
    cp "$TMP_REPORT" "$REPORT_FILE"
  fi
  rm -f "$TMP_REPORT"

  {
    printf '# macOS MDM Audit Report\n\n'
    printf '%s\n' "- Generated report: \`$(basename "$REPORT_FILE")\`"
    printf '%s\n' '- Source script: `mdm-audit.sh`'
    printf '%s\n\n' '- Mode: read-only audit'
    printf '```text\n'
    cat "$REPORT_FILE"
    printf '```\n'
  } >"$MARKDOWN_FILE"

  printf '\nReport saved to: %s\n' "$REPORT_FILE"
  printf 'Markdown report saved to: %s\n' "$MARKDOWN_FILE"
  exit "$run_status"
fi

RED='\033[1;31m'
GRN='\033[1;32m'
YEL='\033[1;33m'
BLU='\033[1;34m'
NC='\033[0m'

info() { printf "${BLU}[*]${NC} %s\n" "$*"; }
ok() { printf "${GRN}[OK]${NC} %s\n" "$*"; }
warn() { printf "${YEL}[WARN]${NC} %s\n" "$*"; }
bad() { printf "${RED}[FINDING]${NC} %s\n" "$*"; }

run_cmd() {
  local title=$1
  shift
  printf '\n%s\n' "--- ${title} ---"
  if "$@" 2>&1; then
    return 0
  else
    warn "Command failed or unavailable: $*"
    return 0
  fi
}

check_path() {
  local path=$1
  if [[ -e "$path" ]]; then
    ok "Exists: $path"
    ls -ldO "$path" 2>/dev/null || ls -ld "$path" 2>/dev/null || true
  else
    warn "Missing: $path"
  fi
}

check_hosts_for_mdm_blocks() {
  local hosts=/etc/hosts
  printf '\n%s\n' '--- Hosts file MDM-related entries ---'
  if [[ ! -r "$hosts" ]]; then
    warn "Cannot read $hosts"
    return 0
  fi

  local matches
  matches=$(grep -En 'deviceenrollment\.apple\.com|mdmenrollment\.apple\.com|iprofiles\.apple\.com|gdmf\.apple\.com' "$hosts" || true)
  if [[ -n "$matches" ]]; then
    bad "MDM/Apple enrollment-related hosts entries found:"
    printf '%s\n' "$matches"
  else
    ok "No obvious MDM enrollment host overrides found"
  fi
}

check_profile_store() {
  printf '\n%s\n' '--- Configuration profile store ---'
  check_path /var/db/ConfigurationProfiles
  check_path /var/db/ConfigurationProfiles/Store

  if [[ -d /var/db/ConfigurationProfiles/Store ]]; then
    local count
    count=$(find /var/db/ConfigurationProfiles/Store -maxdepth 1 -mindepth 1 2>/dev/null | wc -l | tr -d ' ' || true)
    info "Store entry count: ${count:-unknown}"
  fi
}

check_setup_assistant_markers() {
  printf '\n%s\n' '--- Setup Assistant markers ---'
  check_path /var/db/.AppleSetupDone
  check_path /var/db/com.apple.SetupAssistant.plist
}

check_profiles_ui() {
  printf '\n%s\n' '--- Profiles UI presence ---'
  check_path /System/Library/PreferencePanes/Profiles.prefPane
  check_path /System/Library/PreferencePanes/Profiles.prefPane.bak
  if [[ -e /System/Library/PreferencePanes/Profiles.prefPane.bak ]]; then
    bad "Profiles.prefPane backup/rename artifact exists"
  fi
}

check_launchctl_mdm() {
  printf '\n%s\n' '--- ManagedClient enrollment launchd state ---'
  if command -v launchctl >/dev/null 2>&1; then
    launchctl print-disabled system 2>/dev/null | grep -E 'ManagedClient|mdm|MDM' || ok "No obvious disabled ManagedClient/MDM entries shown"
  else
    warn "launchctl unavailable"
  fi
}

check_logs_hint() {
  printf '\n%s\n' '--- Suggested log queries ---'
  cat <<'EOF'
For deeper investigation, run this script with:
  ./mdm-audit.sh --collect-logs

Or run these manually as an administrator:
  log show --last 24h --predicate 'process == "mdmclient"' --info
  log show --last 24h --predicate 'subsystem CONTAINS[c] "ManagedClient" OR eventMessage CONTAINS[c] "MDM"' --info
  log show --last 24h --predicate 'eventMessage CONTAINS[c] "ConfigurationProfiles"' --info
EOF
}

collect_mdm_logs() {
  printf '\n%s\n' '--- Optional MDM log collection ---'
  if ! command -v log >/dev/null 2>&1; then
    warn "log command unavailable"
    return 0
  fi

  local log_file
  log_file="${LOG_FILE:-${REPORT_FILE%.txt}.logs.txt}"
  info "Collecting recent read-only MDM-related logs into: $log_file"
  {
    printf 'macOS MDM Related Unified Logs\n'
    printf 'Generated: %s\n' "$(date)"
    printf '\n--- mdmclient, last 24h ---\n'
    log show --last 24h --predicate 'process == "mdmclient"' --info 2>&1 || true
    printf '\n--- ManagedClient or MDM messages, last 24h ---\n'
    log show --last 24h --predicate 'subsystem CONTAINS[c] "ManagedClient" OR eventMessage CONTAINS[c] "MDM"' --info 2>&1 || true
    printf '\n--- ConfigurationProfiles messages, last 24h ---\n'
    log show --last 24h --predicate 'eventMessage CONTAINS[c] "ConfigurationProfiles"' --info 2>&1 || true
  } >"$log_file"
  ok "Log collection saved: $log_file"
}

main() {
  printf 'macOS MDM Read-Only Audit\n'
  printf 'Generated: %s\n' "$(date)"
  printf 'User: %s  EUID: %s\n' "${USER:-unknown}" "$EUID"

  run_cmd 'macOS version' sw_vers
  run_cmd 'Hardware overview' system_profiler SPHardwareDataType

  if command -v profiles >/dev/null 2>&1; then
    run_cmd 'MDM enrollment status' profiles status -type enrollment
    run_cmd 'Installed configuration profiles' profiles list
  else
    warn "profiles command unavailable"
  fi

  if command -v fdesetup >/dev/null 2>&1; then
    run_cmd 'FileVault status' fdesetup status
  fi

  if command -v csrutil >/dev/null 2>&1; then
    run_cmd 'SIP status' csrutil status
    run_cmd 'Authenticated root status' csrutil authenticated-root status
  fi

  check_profile_store
  check_setup_assistant_markers
  check_profiles_ui
  check_hosts_for_mdm_blocks
  check_launchctl_mdm
  if $COLLECT_LOGS; then
    collect_mdm_logs
  else
    check_logs_hint
  fi

  printf '\nAudit complete. No system changes were made.\n'
}

main "$@"
