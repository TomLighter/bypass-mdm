#!/bin/bash
set -euo pipefail
shopt -s nullglob

# Bootstrapper for the read-only macOS MDM audit script.
# Downloads mdm-audit.sh, verifies its SHA-256, saves it to a writable location, and runs it.
# This script does not modify MDM settings, profiles, services, or system configuration.

GITHUB_USER=${GITHUB_USER:-TomLighter}
GITHUB_REPO=${GITHUB_REPO:-bypass-mdm}
BRANCH=${BRANCH:-v0.1-audit}
AUDIT_SCRIPT=${AUDIT_SCRIPT:-mdm-audit.sh}
AUDIT_SHA256=${AUDIT_SHA256:-d8499303840df6fcbf0954f53aa5b5ddcf93cfab8f0301ecd2d926fbdfe4370f}
RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}/${AUDIT_SCRIPT}"

log() { printf '[*] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: ./mdm-audit-bootstrap.sh [--collect-logs]

Downloads, verifies, and runs the read-only mdm-audit.sh script.

Options passed through to mdm-audit.sh:
  --collect-logs   Save recent read-only MDM-related unified logs next to the report
  -h, --help       Show this help

Environment overrides:
  DEST=/path              Save downloaded script and reports under this path
  REPORT_DIR=/path        Save reports under this path
  BRANCH=name             Git branch or tag to download from, default: v0.1-audit
  AUDIT_SHA256=hex        Expected SHA-256 for mdm-audit.sh
  AUDIT_SHA256=skip       Skip SHA-256 verification, not recommended
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    --collect-logs)
      ;;
    *)
      printf 'Unknown option: %s\n' "$arg" >&2
      printf 'Run ./mdm-audit-bootstrap.sh --help for usage.\n' >&2
      exit 2
      ;;
  esac
done

choose_dest() {
  local candidate

  # In Recovery, prefer a mounted Data volume's Users/Shared so reports survive reboot.
  for candidate in /Volumes/*/Users/Shared; do
    [[ -d "$candidate" ]] || continue
    if [[ -w "$candidate" ]] || mkdir -p "$candidate" 2>/dev/null; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  # Then use current directory if writable.
  if [[ -w . ]]; then
    pwd
    return 0
  fi

  # Fallback for normal macOS or limited Recovery shells.
  printf '%s\n' /tmp
}

sha256_file() {
  local file=$1
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file" | awk '{print $NF}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    return 1
  fi
}

verify_download() {
  local file=$1 actual

  if [[ "$AUDIT_SHA256" == "skip" ]]; then
    warn "SHA-256 verification skipped by AUDIT_SHA256=skip"
    return 0
  fi

  actual=$(sha256_file "$file" || true)
  if [[ -z "$actual" ]]; then
    warn "No SHA-256 tool available; refusing to run downloaded script."
    exit 1
  fi

  log "Expected SHA-256: $AUDIT_SHA256"
  log "Actual SHA-256  : $actual"
  if [[ "$actual" != "$AUDIT_SHA256" ]]; then
    warn "SHA-256 mismatch; refusing to run downloaded script."
    warn "If mdm-audit.sh changed intentionally, update AUDIT_SHA256 in this bootstrapper."
    exit 1
  fi
}

DEST="${DEST:-$(choose_dest)}"
mkdir -p "$DEST"

log "Using destination: $DEST"
log "Downloading read-only audit script from: $RAW_URL"

if ! curl -fsSL "$RAW_URL" -o "${DEST}/${AUDIT_SCRIPT}"; then
  warn "Download failed: $RAW_URL"
  exit 1
fi

verify_download "${DEST}/${AUDIT_SCRIPT}"
chmod +x "${DEST}/${AUDIT_SCRIPT}"

# Keep reports next to the downloaded script unless caller explicitly sets REPORT_DIR.
export REPORT_DIR="${REPORT_DIR:-${DEST}/reports}"

log "Running read-only audit..."
exec "${DEST}/${AUDIT_SCRIPT}" "$@"
