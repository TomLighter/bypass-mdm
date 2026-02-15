#!/usr/bin/env zsh
set -euo pipefail
setopt null_glob

log()  { print "[*] $1"; }
warn() { print -u2 "[!] $1"; }

# Non-interactive: skip "Run now?" prompt and execute recovery script after SHA verify
AUTO_YES=false
for arg in "${@}"; do
  case "$arg" in
    -y|--yes) AUTO_YES=true; break ;;
  esac
done

GITHUB_USER=${GITHUB_USER:-TomLighter}
GITHUB_REPO=${GITHUB_REPO:-bypass-mdm}
FILE_PATH=${FILE_PATH:-bypass-mdm-cleanup-recovery.sh}
RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main/${FILE_PATH}"
API_URL="https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/contents/${FILE_PATH}"

log "Searching for macOS system and data volumes under /Volumes..."
typeset -a sys_volumes
typeset -a data_volumes
for volume in /Volumes/*; do
  [[ -d "$volume/System/Library/CoreServices" ]] && sys_volumes+=("${volume:t}")
  # Data volume: has private/var/db (firmlink layout) or var/db, or name is "Data" or ends with " - Data"
  if [[ -d "$volume/private/var/db" ]] || [[ -d "$volume/var/db" ]]; then
    data_volumes+=("${volume:t}")
  elif [[ "${volume:t}" == "Data" ]] || [[ "${volume:t}" == *" - Data" ]]; then
    data_volumes+=("${volume:t}")
  fi
done

# Prefer system volume for "which volume to use"; in -y mode never prompt
SYS_VOL=""
DATA_VOL=""
if (( ${#sys_volumes} == 0 )); then
  log "No macOS system volume found. Discovering and mounting APFS volumes..."
  # First try default names
  for try in "Macintosh HD" "Macintosh HD - Data" "Data"; do
    diskutil mount "$try" 2>/dev/null || true
  done
  # Discover all APFS volume names from diskutil (handles custom names like "My SSD" / "My SSD - Data")
  # Output format: "   Name:                Macintosh HD - Data" or "Name: My SSD (Case-sensitive)"
  typeset -a apfs_names
  apfs_names=("${(f)$(diskutil apfs list 2>/dev/null | sed -n 's/^[[:space:]]*Name:[[:space:]]*\(.*\)/\1/p' | sed 's/[[:space:]]*(Case-sensitive).*//' | sed 's/[[:space:]]*(Case-insensitive).*//' | sed 's/[[:space:]]*$//')}")
  for name in "${apfs_names[@]}"; do
    [[ -z "$name" ]] && continue
    case "${(L)name}" in
      preboot|recovery|vm|update) continue ;;
      *) diskutil mount "$name" 2>/dev/null || true ;;
    esac
  done
  sys_volumes=()
  data_volumes=()
  for volume in /Volumes/*; do
    [[ -d "$volume/System/Library/CoreServices" ]] && sys_volumes+=("${volume:t}")
    if [[ -d "$volume/private/var/db" ]] || [[ -d "$volume/var/db" ]]; then
      data_volumes+=("${volume:t}")
    elif [[ "${volume:t}" == "Data" ]] || [[ "${volume:t}" == *" - Data" ]]; then
      data_volumes+=("${volume:t}")
    fi
  done
fi
if (( ${#sys_volumes} == 0 )); then
  warn "No macOS system volume found under /Volumes."
  warn "Mount your System and Data volumes first, e.g.:  diskutil mount \"Macintosh HD\" ; diskutil mount \"Macintosh HD - Data\""
  warn "On Apple Silicon the Data volume is often named \"Data\". Use: diskutil apfs list  to see your volume names."
  exit 1
fi

if (( ${#sys_volumes} == 1 )); then
  SYS_VOL=${sys_volumes[1]}
  log "Detected system volume: $SYS_VOL"
else
  if $AUTO_YES; then
    # Non-interactive: pick first system volume that has a matching Data volume, else first
    SYS_VOL=""
    for vol in "${sys_volumes[@]}"; do
      for d in "${data_volumes[@]}"; do
        if [[ "$d" == "Data" ]] || [[ "$d" == "${vol} - Data" ]]; then
          SYS_VOL="$vol"
          break 2
        fi
      done
    done
    [[ -z $SYS_VOL ]] && SYS_VOL=${sys_volumes[1]}
    log "Multiple system volumes; auto-selected: $SYS_VOL"
  else
    log "Multiple system candidates:"
    integer idx=1
    for vol in "${sys_volumes[@]}"; do
      print "  $idx) $vol"
      (( idx++ ))
    done
    printf 'Select volume number: '
    read -r selection
    if ! [[ $selection =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#sys_volumes} )); then
      warn "Invalid selection."
      exit 1
    fi
    SYS_VOL=${sys_volumes[selection]}
    log "Chosen system volume: $SYS_VOL"
  fi
fi

# Resolve data volume: explicit match for this system (e.g. "Macintosh HD" -> "Macintosh HD - Data" or "Data")
if (( ${#data_volumes} > 0 )); then
  for d in "${data_volumes[@]}"; do
    if [[ "$d" == "Data" ]] || [[ "$d" == "${SYS_VOL} - Data" ]]; then
      DATA_VOL="$d"
      break
    fi
  done
  [[ -z $DATA_VOL ]] && DATA_VOL=${data_volumes[1]}
fi
if [[ -z $DATA_VOL ]]; then
  # Legacy single volume or only system mounted: use system for both
  DATA_VOL="$SYS_VOL"
  log "Using single volume for both data and system: $SYS_VOL"
else
  log "Data volume: $DATA_VOL"
fi

# Writable destination: prefer Data volume's Users/Shared (Users is on Data), then system's, then /tmp
DEST="/Volumes/${DATA_VOL}/Users/Shared"
if ! mkdir -p "$DEST" 2>/dev/null; then
  DEST="/Volumes/${SYS_VOL}/Users/Shared"
  if ! mkdir -p "$DEST" 2>/dev/null; then
    warn "Could not create ${DEST}; using /tmp instead."
    DEST="/tmp"
    mkdir -p "$DEST"
  fi
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
if $AUTO_YES; then
  log "Executing ${DEST}/${FILE_PATH} with Data=$DATA_VOL System=$SYS_VOL ..."
  /bin/zsh "${DEST}/${FILE_PATH}" "$DATA_VOL" "$SYS_VOL"
else
  printf 'Run the recovery script now? (y/N): '
  read -r answer
  if [[ $answer == [yY] ]]; then
    log "Executing ${DEST}/${FILE_PATH} with Data=$DATA_VOL System=$SYS_VOL ..."
    /bin/zsh "${DEST}/${FILE_PATH}" "$DATA_VOL" "$SYS_VOL"
  else
    log "Saved to ${DEST}/${FILE_PATH}. Run manually when ready (e.g. ${DEST}/${FILE_PATH} \"$DATA_VOL\" \"$SYS_VOL\")."
  fi
fi
