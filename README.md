# bypass-mdm

## MDM bypass and cleanup 
## Use only on devices you own or have permission to modify.

## Files



- bypass-mdm-cleanup.sh — run in normal macOS (admin/root) for a best-effort cleanup. This script attempts to remove MDM profiles and related configurations from the system.
- bypass-mdm-cleanup-recovery.sh — run from Recovery Terminal for persistent changes (UI hide + snapshot). Accepts optional [DataVol] [SysVol] (defaults for Tahoe/Catalina+ split volumes). Designed for recovery mode; supports macOS Tahoe 26.3.
- bypass-bootstrap.sh — Recovery helper that downloads the latest recovery script from GitHub and verifies its SHA before execution (optional). This script serves as a bootstrap utility to fetch and validate the recovery script from a remote source.

## WARNING
Snapshot / bless behavior varies by macOS version and Apple Silicon vs Intel (e.g. Tahoe 26.3: `--setBoot` on Apple Silicon, `--bootefi` on Intel). Test on a disposable machine before using widely. Scripts modify system areas — backup first.

## Usage (normal macOS)
1. Save bypass-mdm-cleanup.sh and mark executable:
```bash
chmod +x bypass-mdm-cleanup.sh
sudo ./bypass-mdm-cleanup.sh
```

---

## mdm-cleanup-tool

Forced MDM UI hide + cleanup scripts  
Use only on machines you own or have explicit permission to modify.

### What this repo is

This repo contains two scripts that help neutralize local MDM enrollment nags and forcibly hide the macOS Device Management / Profiles UI:

- bypass-mdm-cleanup.sh — best-effort cleanup you can run from a normal booted macOS (requires admin).
- bypass-mdm-cleanup-recovery.sh — Recovery Terminal script that performs the forced UI hide, locks the local store, and (if possible) creates a sealed snapshot for persistence.
- The scripts modify system files, set immutable flags, and may create sealed snapshots. Exact behavior can vary by macOS version and platform (Apple Silicon vs Intel). Proceed with caution.

---

### Quick summary (why)

- Removes local configuration profile artifacts that trigger the enrollment prompt.
- Makes the /var/db/ConfigurationProfiles/Store directory read-only and immutable (schg,datavault) so the local client can’t rewrite the stubs.
- Renames/hides Profiles.prefPane so System Settings cannot surface the enrollment UI.
- Marks Setup Assistant steps as completed to stop setup re-prompts.

This only affects the local machine.  
[Unverified] If the device is registered in a server-side DEP/MDM service, those server records remain — only the server admin or Apple can remove server-side enrollment.

---

### Important warnings (read this first)

- Backup first. Create a Time Machine backup or disk image.
- Do not use on devices you don’t own or are not authorized to modify — doing so may violate policy or law.
- Snapshot / bless and authenticated-root behavior differ across macOS builds; the Recovery script may need small edits for your exact macOS version.
- Major macOS updates can revert changes — re-run checks after updates.
- Bootstrap fetches scripts over HTTPS and verifies SHA via the GitHub API; there is no TLS pinning. For reproducibility, use a specific branch or tag URL and confirm the source before running.

---

### File list

- bypass-bootstrap.sh — Recovery helper for downloading/verifying the recovery script.
- bypass-mdm-cleanup-recovery.sh — run from Recovery Terminal for persistent UI hide.
- bypass-mdm-cleanup.sh — run from normal macOS terminal as admin.
- README.md — this file.

---

### Pre-requisites

- You must be admin on the Mac (normal script), and Recovery Terminal access is required for the Recovery script.
- For persistent UI hide you will likely need to disable authenticated root (Recovery):
```bash
csrutil authenticated-root disable
```
Reboot into Recovery again after disabling if required by your macOS version. (don't forget to enable this afterwards)

---

### Usage — Normal macOS (best effort)

1. Save bypass-mdm-cleanup.sh and make executable:
```bash
chmod +x bypass-mdm-cleanup.sh
sudo ./bypass-mdm-cleanup.sh
```

2. Reboot and check:
```bash
profiles status -type enrollment
sudo ls -alO /var/db/ConfigurationProfiles/Store
```

Note: hiding the Profiles pref pane from normal macOS may not persist across updates; Recovery script is recommended for persistence.

---

### Usage — Recovery (recommended for persistent UI hide)

On **macOS Catalina through Tahoe** (including Tahoe 26.3, the current release), the boot volume is split: **System volume** (e.g. `Macintosh HD`) has `/System`; **Data volume** (`Macintosh HD - Data` on Intel, `Data` on Apple Silicon) has `/var/db` via the firmlink `private` (on-disk path on the Data volume is `private/var/db`). Both volumes must be mounted in Recovery. The recovery script accepts optional `[DataVol] [SysVol]` and auto-defaults to these names when only one volume was used on older Macs.

#### Fully automatic (copy-paste once)

Do this in order. No typing required except pasting the block.

**Before you start (do once):**
1. Boot into Recovery (Apple Silicon: hold Power, tap Options, choose Recovery; Intel: hold ⌘+R at boot).
2. In Recovery, connect to Wi‑Fi (menu bar or Utilities) so the script can download.
3. Disable authenticated root (required for the snapshot step): open Terminal from Utilities → Terminal, run `csrutil authenticated-root disable`, then `reboot`. After reboot, go back into Recovery (step 1 again).

**Then paste this single block** (it discovers and mounts your APFS volumes by name—including custom names—then downloads the script, verifies it, and runs it with no prompts; the Mac will reboot when done):

```bash
curl -sL https://raw.githubusercontent.com/TomLighter/bypass-mdm/main/bypass-bootstrap.sh -o /tmp/boot.sh && chmod +x /tmp/boot.sh && /tmp/boot.sh -y
```

The script uses `diskutil apfs list` to find all APFS volume names (e.g. "Macintosh HD", "My SSD - Data") and mounts them automatically, so you don't need to type or edit volume names. It then cleans the Data volume, hides the pref pane on the System volume, creates a snapshot, and reboots.

**When it’s not fully automatic:** If the internal disk is FileVault‑encrypted, you may be asked for the password when the script tries to mount volumes. If you have multiple macOS disks (e.g. internal + external), the script picks the first suitable one when run with `-y`; to choose a different disk, run without `-y` and select the volume number when prompted.

#### Seamless recovery (one command after mounts)

If you already mounted both volumes (or prefer to mount them yourself):

1. Mount both volumes (edit names if yours differ):
```bash
diskutil apfs list
diskutil mount "Macintosh HD"
diskutil mount "Macintosh HD - Data"   # or "Data" on Apple Silicon
```

2. Run the one-liner (downloads bootstrap, verifies SHA, runs recovery script with `-y`; no prompt):
```bash
curl -sL https://raw.githubusercontent.com/TomLighter/bypass-mdm/main/bypass-bootstrap.sh -o /tmp/boot.sh && chmod +x /tmp/boot.sh && /tmp/boot.sh -y
```

The script will clean the Data volume, hide the pref pane on the System volume, create a snapshot (using `--setBoot` on Apple Silicon, `--bootefi` on Intel), and reboot.

#### Recovery flow (manual)

1. Boot into Recovery:  
- Apple Silicon: hold Power → Options → Continue.  
- Intel: hold ⌘+R at boot.

2. (If needed) Disable authenticated root:
```bash
csrutil authenticated-root disable
reboot
```
Then re-enter Recovery.

3. Mount system and Data volumes:
```bash
diskutil apfs list        # find your volume names if unsure
diskutil mount "Macintosh HD"
diskutil mount "Macintosh HD - Data"   # or "Data" on Apple Silicon
```

4. Fetch the Recovery script and run it (args optional: `[DataVol] [SysVol]`):
```bash
curl -L https://raw.githubusercontent.com/TomLighter/bypass-mdm/main/bypass-mdm-cleanup-recovery.sh -o /tmp/mdm-cleanup-recovery.sh
chmod +x /tmp/mdm-cleanup-recovery.sh
# Inspect before running:
sed -n '1,120p' /tmp/mdm-cleanup-recovery.sh
# Then run (defaults work for Tahoe; pass names if different):
/tmp/mdm-cleanup-recovery.sh
# Or explicitly: /tmp/mdm-cleanup-recovery.sh "Macintosh HD - Data" "Macintosh HD"
```

The script will:

- remove /var/db/ConfigurationProfiles, MDM, lockdown stubs on the **Data** volume,
- recreate and lock the Store folder with chmod 000 + chflags schg,datavault,
- rename /System/Library/PreferencePanes/Profiles.prefPane to .bak on the **System** volume,
- create a sealed snapshot via bless (Apple Silicon: `--setBoot`; Intel: `--bootefi`),
- reboot.

5. After reboot, verify:
```bash
profiles status -type enrollment
ls -alO /var/db/ConfigurationProfiles/Store
```
System Settings -> Device Management  # UI check

#### Alternative: bootstrap helper (boot into recovery)

After mounting your volumes, run the bootstrap (use `-y` to run the recovery script without prompting):

```bash
curl -sL https://raw.githubusercontent.com/TomLighter/bypass-mdm/main/bypass-bootstrap.sh -o /tmp/bypass-bootstrap.sh
chmod +x /tmp/bypass-bootstrap.sh
/tmp/bypass-bootstrap.sh -y
```

The helper detects system and Data volumes, downloads `bypass-mdm-cleanup-recovery.sh`, verifies its SHA, and runs it with the correct volume names. Integrity is verified against the GitHub API over HTTPS (no TLS pinning). For reproducibility, use a specific branch or commit URL and confirm the script source before running.

---

### Revert instructions (boot into recovery recommended)

If you need to undo the changes (restore pref pane and remove immutable flags), run in Recovery. On Catalina-through-Tahoe split volumes use the **Data** volume for the Store and the **System** volume for the pref pane and bless. The block below uses default volume names; if yours differ (e.g. `Data` and `Macintosh HD` on Apple Silicon), replace the volume names in the paths.

```bash
# Run from Recovery Terminal. Mount both volumes first if needed.

# Data volume: clear immutable flags (path is private/var/db per firmlink layout)
chflags noschg,nodatavault "/Volumes/Macintosh HD - Data/private/var/db/ConfigurationProfiles/Store"
chmod 755 "/Volumes/Macintosh HD - Data/private/var/db/ConfigurationProfiles/Store"

# System volume: restore Profiles.prefPane and create new snapshot
mv "/Volumes/Macintosh HD/System/Library/PreferencePanes/Profiles.prefPane.bak" \
   "/Volumes/Macintosh HD/System/Library/PreferencePanes/Profiles.prefPane"
# Apple Silicon:
"/Volumes/Macintosh HD/usr/sbin/bless" --mount "/Volumes/Macintosh HD" --setBoot --create-snapshot
# Intel (use this instead of the line above):
# "/Volumes/Macintosh HD/usr/sbin/bless" --mount "/Volumes/Macintosh HD" --bootefi --create-snapshot
reboot
```

---

### FAQ

**Q:** Will this remove server-side DEP/MDM records?  
**A:** No — this is local cleanup only. Server/DEP registration (the organization’s console) is not removed by local script.

**Q:** Will future macOS updates re-enable the UI?  
**A:** Possibly. Major OS updates can revert changes; re-run sanity checks after updates.

**Q:** Can this harm the system?  
**A:** The scripts operate on system areas and set immutable flags — they are potentially disruptive if misused. Back up before running. Use Recovery to revert.

**Q:** Is it legal to run these scripts?  
**A:** If you own the device or have explicit permission, yes — otherwise running them could violate policies, contracts, or law. Check policy + legal constraints before using.

---

### Safety & legal

- use at your own risk

---
