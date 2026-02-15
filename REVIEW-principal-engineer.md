# Principal Apple Engineer Review: bypass-mdm

Review of the MDM bypass/cleanup scripts for correctness, robustness, and alignment with macOS behavior on Tahoe 26.3 and split-volume layouts.

---

## Executive summary

- **Critical:** Data volume paths are wrong. On the Data volume, `/var` lives under the firmlink target `private`; the correct path is `private/var/db`, not `var/db`. Without this fix, cleanup and locking on the Data volume do nothing on real split-volume installs.
- **High:** Several robustness and compatibility items (bless usage, single-volume fallback, revert docs) need small corrections.
- **Medium:** Security and operational notes (TLS, Recovery environment, SIP) are documented; a few clarifications recommended.
- **Low:** Minor hardening (quoting, error handling) and doc tweaks.

No approval of the *purpose* of these scripts (bypassing MDM) is implied; this review is about technical correctness and maintainability.

---

## 1. Critical: Data volume path (firmlink layout)

**Issue:** The recovery script and README use `$DATA_TARGET/var/db/...` for the Data volume. On APFS split volumes, the Data volume is joined via firmlinks. The mapping is `/private` → `private` (on Data). So `/var` (which is `/private/var`) on the live system corresponds to the directory **`private/var`** on the Data volume root, not `var` at the root. When you mount "Macintosh HD - Data" in Recovery, the path to the configuration store is:

- **Wrong:** `"/Volumes/Macintosh HD - Data/var/db/ConfigurationProfiles"`
- **Correct:** `"/Volumes/Macintosh HD - Data/private/var/db/ConfigurationProfiles"`

References: `/usr/share/firmlinks` (System volume), Apple WWDC 2019 “What’s New in Apple File Systems,” and [Swift Forensics](https://www.swiftforensics.com/2019/10/macos-1015-volumes-firmlink-magic.html). User reports and Apple discussions confirm that in Recovery the Data volume exposes this as `.../private/var` (e.g. [Apple discussions](https://discussions.apple.com/thread/255586335)).

**Impact:** On any Mac with a split System/Data layout (Catalina and later, including Tahoe 26.3), the recovery script currently creates and locks a **nonexistent** `var/db/ConfigurationProfiles/Store` on the Data volume (or fails silently), while the real store at `private/var/db/ConfigurationProfiles/Store` is untouched. So MDM cleanup and locking are ineffective on the real location.

**Fix:** Use `private/var/db` on the Data volume in:

- `bypass-mdm-cleanup-recovery.sh`: all `DATA_TARGET` paths for ConfigurationProfiles, MDM, lockdown, SetupAssistant.
- README revert section: path for clearing flags and chmod on the Data volume.

**Legacy single volume:** On a single pre-Catalina volume, the same volume has both System and Data content; the writable hierarchy is still under `private` (e.g. `private/var/db`). So using `private/var/db` is correct for both split and single-volume layouts.

---

## 2. bless and snapshot behavior

- **Apple Silicon:** Use of `--setBoot --create-snapshot` for the system volume is correct for internal SSVs on 12.3.1+.
- **Intel:** `--bootefi --create-snapshot` is appropriate.
- **Recommendation:** Keep the `|| true` so snapshot failure does not abort the script; consider logging the exit code or blessing stderr when it fails so users can diagnose (e.g. authenticated-root, sealing, or bless changes in future OS versions).
- **Fixed:** bless is now run without swallowing stderr; on failure the script prints exit code and a short hint (e.g. ensure authenticated-root is disabled). Script continues so user can see bless stderr and reboot.

---

## 3. Volume detection and bootstrap

- **System vs Data:** Correct that the “system” volume is identified by `System/Library/CoreServices` and the Data volume by `var/db` or by name. For consistency with the path fix above, the “has var/db” check for the Data volume should look for **`private/var/db`** (or accept either `var/db` or `private/var/db`) so that when only the Data volume is mounted we still detect it correctly.
- **Single volume:** When only the system volume is mounted, using it for both DATA_VOL and SYS_VOL is a reasonable fallback; the recovery script then operates on one volume. On a true split-volume machine, the user must mount both; the README already states that.
- **DEST:** Preferring Data volume’s `Users/Shared` then system’s then `/tmp` is correct; `Users` lives on the Data volume.

---

## 4. In-system script (bypass-mdm-cleanup.sh)

- Runs against the live root; paths like `/var/db` and `/System/Library/PreferencePanes` are the unified view and are correct. No volume path change needed.
- `mount -uw /` may not make the system volume writable on a sealed system; the script’s note that persistence may require Recovery is appropriate.
- `launchctl disable system/com.apple.ManagedClient.enroll` is the right service. No change required for Tahoe 26.x from a path/layout perspective.

---

## 5. Security and operational notes

- **Bootstrap:** SHA verification against the GitHub API (over HTTPS) gives integrity and origin with respect to the repo; no TLS pinning. Acceptable for this use case; document that users should check the URL and consider branch/commit if they need reproducibility.
- **Fixed:** README now documents (Important warnings + bootstrap section) that there is no TLS pinning and that for reproducibility users should use a specific branch/tag URL and confirm the source.
- **Recovery:** Scripts assume root and Recovery environment (e.g. `mount -uw`, `bless`). README correctly states that authenticated-root must be disabled for snapshot creation.
- **Revert:** Revert steps should use the same **Data** path as the script: `private/var/db/ConfigurationProfiles/Store` on the Data volume, and System volume for pref pane and bless. README should show both Apple Silicon and Intel bless commands clearly (as it does) and use the corrected Data path. **Fixed.**

---

## 6. Minor robustness and docs

- **Quoting:** All `$DATA_TARGET`, `$SYS_TARGET`, and volume names in commands are quoted; good. Keep this for volume names with spaces.
- **set -e:** With `|| true` on rm/chmod/chflags/bless, the script does not exit on those failures. Intentional; consider one-line comments so future maintainers don’t “fix” by removing `|| true` and then breaking on first failure.
- **Fixed:** Recovery script has “Intentional || true” (or similar) comments above each such line; in-system script has a block comment explaining best-effort and || true.
- **README:** Clarify that “Tahoe 26.3” refers to the current macOS release and that the same layout applies to Catalina through Tahoe. Revert section: use concrete placeholders (e.g. `Macintosh HD - Data` and `Macintosh HD`) in the example block and then say “replace with your volume names if different” so the copy-paste works on default names.
- **Fixed:** README now says “macOS Catalina through Tahoe (including Tahoe 26.3, the current release)”. Revert block uses literal “Macintosh HD - Data” and “Macintosh HD” with a sentence telling users to replace if their names differ.

---

## 7. Checklist after applying fixes

- [x] Recovery script uses `private/var/db` for all Data-volume paths (ConfigurationProfiles, MDM, lockdown, SetupAssistant).
- [x] Bootstrap data-volume detection accepts `private/var/db` (and optionally `var/db` for robustness).
- [x] README revert instructions use `.../private/var/db/ConfigurationProfiles/Store` for the Data volume.
- [x] README notes that Data volume layout uses `private/var` (firmlink) so paths under the Data mount are `private/var/db/...`.
- [ ] Test on a Tahoe 26.x machine (or equivalent) with split volumes: verify Store is created and locked under `private/var/db`, and that revert restores the correct path.

---

## Conclusion

The main change required for correctness on Tahoe 26.3 (and all split-volume macOS) is to use **`private/var/db`** on the Data volume everywhere instead of **`var/db`**. With that and the small doc/robustness items above, the design (separate Data vs System targets, bless flags per arch, bootstrap with SHA and `-y`) is sound and aligned with current macOS behavior.
