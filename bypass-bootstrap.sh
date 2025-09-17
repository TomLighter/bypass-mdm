#!/usr/bin/env zsh
set -euo pipefail
setopt null_glob

log()  { print "[*] $1"; }
warn() { print -u2 "[!] $1"; }

GITHUB_USER=${GITHUB_USER:-TomLighter}
GITHUB_REPO=${GITHUB_REPO:-bypass-mdm}
FILE_PATH=${FILE_PATH:-bypass-mdm-cleanup-recovery.sh}
RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main/${FILE_PATH}"
API_URL="https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/contents/${FILE_PATH}"

log "Searching for macOS system volumes under /Volumes..."
typeset -a volumes
for volume in /Volumes/*; do
  [[ -d "$volume/System/Library/CoreServices" ]] && volumes+=("${volume:t}")
done

if (( ${#volumes} == 0 )); then
  warn "No macOS-looking volume found under /Volumes."
  warn "Mount your Data/System volume first, e.g.:  diskutil mount \"Macintosh HD\""
  exit 1
fi

if (( ${#volumes} == 1 )); then
  SYS_VOL=${volumes[1]}
  log "Detected: $SYS_VOL"
else
  log "Multiple candidates:"
  integer idx=1
  for vol in "${volumes[@]}"; do
    print "  $idx) $vol"
    (( idx++ ))
  done
  printf 'Select volume number: '
  read -r selection
  if ! [[ $selection =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#volumes} )); then
    warn "Invalid selection."
    exit 1
  fi
  SYS_VOL=${volumes[selection]}
  log "Chosen: $SYS_VOL"
fi

DEST="/Volumes/${SYS_VOL}/Users/Shared"
if ! mkdir -p "$DEST" 2>/dev/null; then
  warn "Could not create ${DEST}; using /tmp instead."
  DEST="/tmp"
  mkdir -p "$DEST"
fi

cd "$DEST"

log "Downloading script (HTTP errors will fail)..."
if ! curl -L -f --progress-bar -o "$FILE_PATH" "$RAW_URL"; then
  print
  warn "Download failed."
  warn "Check that the repository '${GITHUB_USER}/${GITHUB_REPO}' exists,"
  warn "the file '${FILE_PATH}' is committed on the 'main' branch,"
  warn "and the raw URL is accessible:"
  warn "  $RAW_URL"
  exit 1
fi
chmod +x "$FILE_PATH"

compute_git_blob_sha() {
  local file=$1 size
  size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
  if [[ -z $size ]]; then
    warn "Unable to determine file size for $file."
    return 1
  fi
  if command -v openssl >/dev/null 2>&1 && command -v xxd >/dev/null 2>&1; then
    printf "blob %s\0" "$size" | cat - "$file" | openssl sha1 -binary | xxd -p -c 256
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 1 "$file" | awk '{print $1}'
  else
    warn "No hashing tool available (openssl/xxd or shasum)."
    return 1
  fi
}

LOCAL_SHA=$(compute_git_blob_sha "$FILE_PATH" || true)
if [[ -z $LOCAL_SHA ]]; then
  warn "Could not compute local SHA; refusing to continue."
  exit 1
fi

API_JSON=$(curl -s -H "Accept: application/vnd.github.v3+json" "$API_URL")
REMOTE_SHA=$(print -r -- "$API_JSON" | tr -d '\r\n' | sed -n 's/.*\"sha\"[[:space:]]*:[[:space:]]*\"\([0-9a-f]\{40\}\)\".*/\1/p')

if [[ -z $REMOTE_SHA ]]; then
  warn "Could not retrieve remote SHA from GitHub."
  warn "GitHub API response:"
  warn "  $API_JSON"
  exit 1
fi

log "Local SHA : $LOCAL_SHA"
log "Remote SHA: $REMOTE_SHA"
if [[ $LOCAL_SHA != $REMOTE_SHA ]]; then
  warn "SHA mismatch — refusing to run to be safe."
  warn "Ensure the file in the repo matches what was downloaded, then retry."
  exit 2
fi

print
log "SHA verified."
printf 'Run the recovery script now? (y/N): '
read -r answer
if [[ $answer == [yY] ]]; then
  log "Executing ${DEST}/${FILE_PATH} ..."
  /bin/zsh "${DEST}/${FILE_PATH}"
else
  log "Saved to ${DEST}/${FILE_PATH}. Run manually when ready."
fi
