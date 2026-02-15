#!/usr/bin/env zsh
set -euo pipefail
setopt null_glob

if [[ $EUID -ne 0 ]]; then
  print -u2 "[!] Run in Recovery as root."
  exit 1
fi

# On Tahoe/Catalina+ split volumes: Data volume has /var/db, System volume has /System and bless.
# Usage: $0 [DataVol] [SysVol]
# Defaults: Data = "Macintosh HD - Data" if present, else "Data"; System = "Macintosh HD"
DATA_VOL="${1:-}"
SYS_VOL="${2:-}"

if [[ -z $DATA_VOL ]] || [[ -z $SYS_VOL ]]; then
  if [[ -d /Volumes/"Macintosh HD - Data" ]]; then
    DATA_VOL="${DATA_VOL:-Macintosh HD - Data}"
  elif [[ -d /Volumes/Data ]]; then
    DATA_VOL="${DATA_VOL:-Data}"
  fi
  SYS_VOL="${SYS_VOL:-Macintosh HD}"
  if [[ -z $DATA_VOL ]]; then
    DATA_VOL="Macintosh HD - Data"
  fi
fi

DATA_TARGET="/Volumes/${DATA_VOL}"
SYS_TARGET="/Volumes/${SYS_VOL}"

if [[ ! -d $DATA_TARGET ]]; then
  print -u2 "[!] Data volume '${DATA_VOL}' not found under /Volumes. Mount it or pass as first argument."
  print -u2 "    Example: diskutil mount \"Macintosh HD - Data\"   or   diskutil mount \"Data\""
  exit 1
fi
if [[ ! -d $SYS_TARGET ]]; then
  print -u2 "[!] System volume '${SYS_VOL}' not found under /Volumes. Mount it or pass as second argument."
  print -u2 "    Example: diskutil mount \"Macintosh HD\""
  exit 1
fi

# On split-volume Macs the Data volume must have private/var/db (firmlink layout). If missing, user likely only mounted System.
if [[ "$DATA_VOL" != "$SYS_VOL" ]] && [[ ! -d "${DATA_TARGET}/private" ]]; then
  print -u2 "[!] Data volume '${DATA_VOL}' does not have the expected layout (no 'private/' folder)."
  print -u2 "    You probably only mounted the System volume. On split-volume Macs you must mount BOTH:"
  print -u2 "      diskutil mount \"Macintosh HD\""
  print -u2 "      diskutil mount \"Macintosh HD - Data\"   (or  diskutil mount \"Data\"  on Apple Silicon)"
  print -u2 "    Then run this script again."
  exit 1
fi

print "[*] Recovery cleanup — Data: ${DATA_TARGET}, System: ${SYS_TARGET}"

# Intentional || true: mount may already be rw or not applicable
mount -uw "$DATA_TARGET" 2>/dev/null || true
mount -uw "$SYS_TARGET" 2>/dev/null || true

# On Data volume, /var is under the firmlink target "private" (i.e. private/var/db)
VAR_DB_DATA="${DATA_TARGET}/private/var/db"
print "[*] Cleaning configuration db (ConfigurationProfiles, MDM, lockdown, SetupAssistant) on Data volume..."
# Intentional || true: paths may be missing or already cleaned
rm -rf "${VAR_DB_DATA}/ConfigurationProfiles" 2>/dev/null || true
rm -rf "${VAR_DB_DATA}/MDM" 2>/dev/null || true
rm -rf "${VAR_DB_DATA}/lockdown" 2>/dev/null || true
rm -f  "${VAR_DB_DATA}/com.apple.SetupAssistant"* 2>/dev/null || true
mkdir -p "${VAR_DB_DATA}/ConfigurationProfiles/Store"
# Intentional || true: chmod/chflags can fail on some volumes (e.g. sealed)
chmod 000 "${VAR_DB_DATA}/ConfigurationProfiles/Store" 2>/dev/null || true
chflags schg,datavault "${VAR_DB_DATA}/ConfigurationProfiles/Store" 2>/dev/null || true

print "[*] Hiding Profiles.prefPane (forced) on System volume"
PREF_PANE="${SYS_TARGET}/System/Library/PreferencePanes/Profiles.prefPane"
if [[ -d $PREF_PANE ]]; then
  # Intentional || true: mv can fail if volume is read-only or already renamed
  mv "$PREF_PANE" "${PREF_PANE}.bak" 2>/dev/null || true
  print "[*] Profiles.prefPane renamed."
else
  print "[*] Profiles.prefPane not present at expected path, skipping rename."
fi

BLESS_BIN="${SYS_TARGET}/usr/sbin/bless"
if [[ -x $BLESS_BIN ]]; then
  print "[*] Creating snapshot (may take a moment)..."
  # Script continues on bless failure so user can see stderr and fix (e.g. authenticated-root)
  case "$(uname -m)" in
    arm64)
      if ! "$BLESS_BIN" --mount "$SYS_TARGET" --setBoot --create-snapshot; then
        print -u2 "[!] bless --setBoot --create-snapshot failed (exit $?). Ensure authenticated-root is disabled."
      fi
      ;;
    *)
      if ! "$BLESS_BIN" --mount "$SYS_TARGET" --bootefi --create-snapshot; then
        print -u2 "[!] bless --bootefi --create-snapshot failed (exit $?). See stderr above for details."
      fi
      ;;
  esac
else
  print "[*] bless not available on target mount; snapshot step skipped."
fi

print "[*] Done. Remove immutable flags and restore Profiles.prefPane.bak to revert."
print "[*] Rebooting into macOS..."
reboot
