# bypass-mdm

Use only on devices you own or have permission to modify.  
Local MDM cleanup: removes enrollment prompts and hides the Device Management UI. Backup first; use at your own risk.

**Quick link (for Recovery browser):** [github.com/TomLighter/bypass-mdm](https://github.com/TomLighter/bypass-mdm) — or create a short URL (e.g. [bit.ly](https://bit.ly), [t.ly](https://t.ly)) pointing here and bookmark it so you can open the repo fast in Recovery.

---

## For most users: run from Recovery (recommended)

Do this if you want the cleanup to stick. You’ll boot into Recovery, do three one-time steps, then paste one command.

### Step 1 — Boot into Recovery

- **Apple Silicon:** Hold Power, tap **Options**, choose **Recovery**.
- **Intel:** Restart and hold **⌘ + R** until you see the Apple logo.

### Step 2 — Connect Wi‑Fi and disable authenticated root (one time)

1. In Recovery, connect to Wi‑Fi (menu bar or **Utilities**).
2. Open **Utilities → Terminal**.
3. Run:
   ```bash
   csrutil authenticated-root disable
   reboot
   ```
4. After the Mac restarts, boot into Recovery again (Step 1).

### Step 3 — Paste this in Recovery Terminal

Open **Utilities → Terminal** in Recovery, then paste this and press Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/TomLighter/bypass-mdm/main/bypass-bootstrap.sh -o /tmp/boot.sh && /bin/bash /tmp/boot.sh -y
```

The script will find your disk, download and verify the cleanup script, run it, then reboot. No need to type volume names—it discovers them.

**If FileVault is on,** you may be asked for your disk password when it mounts.  
**If you have several macOS disks,** it uses the first one; to pick another, run without `-y` and choose when prompted.

---

## Revert (undo the changes)

Boot into Recovery, open Terminal, mount your volumes if needed, then run (replace volume names if yours differ—e.g. `Data` instead of `Macintosh HD - Data` on Apple Silicon):

```bash
chflags noschg,nodatavault "/Volumes/Macintosh HD - Data/private/var/db/ConfigurationProfiles/Store"
chmod 755 "/Volumes/Macintosh HD - Data/private/var/db/ConfigurationProfiles/Store"
mv "/Volumes/Macintosh HD/System/Library/PreferencePanes/Profiles.prefPane.bak" "/Volumes/Macintosh HD/System/Library/PreferencePanes/Profiles.prefPane"
"/Volumes/Macintosh HD/usr/sbin/bless" --mount "/Volumes/Macintosh HD" --setBoot --create-snapshot
reboot
```

On Intel, use `--bootefi` instead of `--setBoot` in the bless command.

---

## Optional: run from normal macOS (weaker, may not persist)

Only use this if you can’t use Recovery. Changes may be reverted by updates.

```bash
chmod +x bypass-mdm-cleanup.sh
sudo ./bypass-mdm-cleanup.sh
```

Reboot and check: `profiles status -type enrollment`. For a lasting fix, use the Recovery steps above.

---

## Warnings

- Backup first (e.g. Time Machine).
- Only on devices you own or are allowed to modify.
- Scripts modify system areas and set immutable flags; major updates can undo changes.
- This does **not** remove server-side DEP/MDM; only local cleanup.

---

## Files in this repo

- **bypass-bootstrap.sh** — Fetches and runs the recovery script (used by the one-liner above).
- **bypass-mdm-cleanup-recovery.sh** — Recovery script: cleans MDM data, hides Profiles UI, creates snapshot.
- **bypass-mdm-cleanup.sh** — In-system best-effort cleanup (optional; Recovery is preferred).

---

## FAQ

**Q:** Does this remove server-side DEP/MDM?  
**A:** No. Only local cleanup. Server records stay until the org or Apple removes them.

**Q:** Will updates re-enable the UI?  
**A:** Sometimes. Re-check after major macOS updates.

**Q:** Safe?  
**A:** Scripts change system files. Back up first; you can revert from Recovery (see Revert above).

**Q:** Legal?  
**A:** Yes if you own the device or have permission. Otherwise check your policy and law.
