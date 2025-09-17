# bypass-mdm

## MDM bypass and cleanup 
## Use only on devices you own or have permission to modify.

## Files
- bypass-mdm-cleanup.sh — run in normal macOS (admin/root) for a best-effort cleanup.
- bypass-mdm-cleanup-recovery.sh — run from Recovery Terminal for persistent changes (UI hide + snapshot). Accepts an optional system volume name argument.
- bypass-bootstrap.sh — Recovery helper that downloads the latest recovery script from GitHub and verifies its SHA before execution (optional).

## WARNING
Snapshot / bless behavior varies by macOS version and Apple Silicon vs Intel. Test on a disposable machine before using widely. Scripts modify system areas — backup first.

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

**Important:** Pass the system volume name as the first argument if your system volume uses a different name (e.g. `"Macintosh HD - Data"`).

#### Recovery flow (short)

1. Boot into Recovery:  
- Apple Silicon: hold Power → Options → Continue.  
- Intel: hold ⌘+R at boot.

2. (If needed) Disable authenticated root:
```bash
csrutil authenticated-root disable
reboot
```
Then re-enter Recovery.

3. Mount your system/data volume if needed:
```bash
diskutil apfs list        # find your Data volume if unsure
diskutil mount "Macintosh HD"   # or the name found in step above
```

4. Fetch the Recovery script from GitHub and run it:
```bash
curl -L https://raw.githubusercontent.com/TomLighter/bypass-mdm/main/bypass-mdm-cleanup-recovery.sh -o /tmp/mdm-cleanup-recovery.sh
chmod +x /tmp/mdm-cleanup-recovery.sh
# Inspect before running:
sed -n '1,200p' /tmp/mdm-cleanup-recovery.sh
# Then run:
/tmp/mdm-cleanup-recovery.sh  # add "Macintosh HD - Data" as an argument if needed
```

The script will:

- remove /var/db/ConfigurationProfiles, MDM, lockdown stubs on the Data volume,
- recreate and lock the Store folder with chmod 000 + chflags schg,datavault,
- rename /System/Library/PreferencePanes/Profiles.prefPane to .bak,
- attempt to create a sealed snapshot via bless --create-snapshot (if available),
- reboot.

5. After reboot, verify:
```bash
profiles status -type enrollment
ls -alO /var/db/ConfigurationProfiles/Store
```
System Settings -> Device Management  # UI check

#### Alternative: bootstrap helper (boot into recovery)

Instead of manually downloading, you can run the bundled bootstrap helper after mounting your system volume:

```bash
cd /Volumes/Macintosh\ HD/Users/Shared  # or any writable path
curl -L https://raw.githubusercontent.com/TomLighter/bypass-mdm/main/bypass-bootstrap.sh -o bypass-bootstrap.sh
chmod +x bypass-bootstrap.sh
./bypass-bootstrap.sh
```

The helper lists available `/Volumes` targets, downloads `bypass-mdm-cleanup-recovery.sh`, verifies its SHA with the GitHub API, and optionally runs it for you.

---

### Revert instructions (boot into recovery recommended)

If you need to undo the changes (restore pref pane and remove immutable flags), run in Recovery:

```bash
# run from Recovery Terminal, edit volume name if needed
chflags noschg,nodatavault /Volumes/"Macintosh HD"/var/db/ConfigurationProfiles/Store
chmod 755 /Volumes/"Macintosh HD"/var/db/ConfigurationProfiles/Store
mv /Volumes/"Macintosh HD"/System/Library/PreferencePanes/Profiles.prefPane.bak \
   /Volumes/"Macintosh HD"/System/Library/PreferencePanes/Profiles.prefPane
# Recreate boot snapshot (Apple Silicon / modern macOS)
"/Volumes/Macintosh HD/usr/sbin/bless" --mount "/Volumes/Macintosh HD" --bootefi --create-snapshot
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

- Only run on devices you own or manage with permission.
- Keep backups.
- Test on a spare/disposable Mac if possible.
- Use this repo for recovery/testing/education only. Do not use on someone else’s corporate device without authorization.

---
