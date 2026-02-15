#!/usr/bin/env zsh
set -euo pipefail
setopt null_glob

# Best-effort MDM cleanup from normal macOS (including Tahoe 26.x). For persistent UI hide, run bypass-mdm-cleanup-recovery.sh from Recovery.

if [[ $EUID -ne 0 ]]; then
  print -u2 "[!] Run as root (e.g. sudo $0)."
  exit 1
fi

print "[*] MDM cleanup. Run with admin privileges."

STORE_DIR="/var/db/ConfigurationProfiles/Store"

# Ensure expected directories exist before applying flags
if [[ ! -d $STORE_DIR ]]; then
  print "[*] Creating $STORE_DIR ..."
  mkdir -p "$STORE_DIR"
fi

# Best-effort below: intentional || true so one failure does not abort the script
# Stop MDM/UI helpers that may repopulate the store immediately
killall mdmclient 2>/dev/null || true
killall "Setup Assistant" 2>/dev/null || true

# Reset Store permissions to allow cleanup
chmod 755 "$STORE_DIR" 2>/dev/null || true
rm -f $STORE_DIR/* 2>/dev/null || true

# Lock Store and apply immutable flags (best effort)
chmod 000 "$STORE_DIR" 2>/dev/null || true
chflags schg,datavault "$STORE_DIR" 2>/dev/null || true
chflags schg,datavault $STORE_DIR/* 2>/dev/null || true

# Disable ManagedClient enrollment agent (best effort)
launchctl disable system/com.apple.ManagedClient.enroll 2>/dev/null || true

# Mark Setup Assistant steps complete
DEFAULTS_PLIST="/var/db/com.apple.SetupAssistant"
/usr/bin/defaults write "$DEFAULTS_PLIST" DidSeeSetup -bool TRUE 2>/dev/null || true
/usr/bin/defaults write "$DEFAULTS_PLIST" DidSeeCloudSetup -bool TRUE 2>/dev/null || true

# Attempt to hide Profiles UI (may revert without Recovery script)
PREF_PANE="/System/Library/PreferencePanes/Profiles.prefPane"
if [[ -d $PREF_PANE ]]; then
  print "[*] Attempting to hide Profiles.prefPane (may require running this from recovery terminal for persistence)..."
  mount -uw / 2>/dev/null || true
  mv "$PREF_PANE" "$PREF_PANE.bak" 2>/dev/null || true
fi

print "[*] Status checks (non-fatal)..."
if ! profiles status -type enrollment 2>/dev/null; then
  print -u2 "[!] Unable to read enrollment status."
fi
if ! ls -alO "$STORE_DIR" 2>/dev/null; then
  print -u2 "[!] Unable to list $STORE_DIR."
fi

print "[*] Done. For persistent UI hide, run bypass-mdm-cleanup-recovery.sh from recovery terminal." 
