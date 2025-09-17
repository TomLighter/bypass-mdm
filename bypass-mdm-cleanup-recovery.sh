#!/usr/bin/env zsh
set -euo pipefail
setopt null_glob

if [[ $EUID -ne 0 ]]; then
  print -u2 "[!] Run in Recovery as root."
  exit 1
fi

SYS_VOL=${1:-"Macintosh HD"}
TARGET="/Volumes/${SYS_VOL}"

if [[ ! -d $TARGET ]]; then
  print -u2 "[!] Volume '${SYS_VOL}' not found under /Volumes. Mount it or pass the correct name."
  exit 1
fi

print "[*] Recovery cleanup target: ${TARGET}"

mount -uw "$TARGET" 2>/dev/null || mount -uw / 2>/dev/null || true

print "[*] Cleaning configuration db (ConfigurationProfiles, MDM, lockdown, SetupAssistant)..."
rm -rf "${TARGET}/var/db/ConfigurationProfiles" 2>/dev/null || true
rm -rf "${TARGET}/var/db/MDM" 2>/dev/null || true
rm -rf "${TARGET}/var/db/lockdown" 2>/dev/null || true
rm -f  "${TARGET}/var/db/com.apple.SetupAssistant"* 2>/dev/null || true
mkdir -p "${TARGET}/var/db/ConfigurationProfiles/Store"
chmod 000 "${TARGET}/var/db/ConfigurationProfiles/Store" 2>/dev/null || true
chflags schg,datavault "${TARGET}/var/db/ConfigurationProfiles/Store" 2>/dev/null || true

print "[*] Hiding Profiles.prefPane (forced)"
PREF_PANE="${TARGET}/System/Library/PreferencePanes/Profiles.prefPane"
if [[ -d $PREF_PANE ]]; then
  mv "$PREF_PANE" "${PREF_PANE}.bak" 2>/dev/null || true
  print "[*] Profiles.prefPane renamed."
else
  print "[*] Profiles.prefPane not present at expected path, skipping rename."
fi

BLESS_BIN="${TARGET}/usr/sbin/bless"
if [[ -x $BLESS_BIN ]]; then
  print "[*] Creating snapshot (may take a moment)..."
  "$BLESS_BIN" --mount "$TARGET" --bootefi --create-snapshot || true
else
  print "[*] bless not available on target mount; snapshot step skipped."
fi

print "[*] Done. Remove immutable flags and restore Profiles.prefPane.bak to revert."
print "[*] Rebooting into macOS..."
reboot
