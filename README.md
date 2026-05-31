# macOS MDM Student Security Project

This repository is being used for a white-hat student project focused on macOS MDM security posture, detection, and hardening.

> Use only on devices you own or are explicitly authorized to assess.

## Recovery quick access

Repository URL:

```text
https://github.com/TomLighter/bypass-mdm
```

Suggested short-link target for Recovery use:

```text
https://github.com/TomLighter/bypass-mdm#run-the-audit
```

QR code for the repository:

![QR code for this repository](https://quickchart.io/qr?text=https%3A%2F%2Fgithub.com%2FTomLighter%2Fbypass-mdm&size=180)

## Read-only audit tool

`mdm-audit.sh` performs a read-only audit. It does **not** modify files, services, profiles, launchd state, or system settings.

### What it checks

- macOS version and hardware overview
- MDM / DEP enrollment status
- Installed configuration profiles
- FileVault status
- SIP and authenticated-root status
- Configuration profile store presence, flags, and permissions
- Setup Assistant marker files
- Profiles preference pane presence
- MDM-related `/etc/hosts` overrides
- Disabled MDM / ManagedClient launchd entries
- Optional recent MDM-related unified logs

### Run the audit

From a cloned copy of this repository:

```bash
./mdm-audit.sh
```

Or paste this one-liner into Terminal to download and run the read-only audit bootstrapper:

```bash
curl -fsSL https://raw.githubusercontent.com/TomLighter/bypass-mdm/v0.1-audit/mdm-audit-bootstrap.sh -o /tmp/mdm-audit-bootstrap.sh && /bin/bash /tmp/mdm-audit-bootstrap.sh
```

The bootstrapper saves reports to a mounted `/Volumes/*/Users/Shared` location when available, which is useful from Recovery Terminal. It verifies the downloaded audit script with SHA-256 before execution. The one-liner is pinned to the `v0.1-audit` release tag rather than moving `main`.

To include recent MDM-related logs:

```bash
curl -fsSL https://raw.githubusercontent.com/TomLighter/bypass-mdm/v0.1-audit/mdm-audit-bootstrap.sh -o /tmp/mdm-audit-bootstrap.sh && /bin/bash /tmp/mdm-audit-bootstrap.sh --collect-logs
```

Reports are automatically saved under:

```text
reports/mdm-audit-YYYY-mm-dd-HHMMSS.txt
reports/mdm-audit-YYYY-mm-dd-HHMMSS.md
```

The terminal output may use color, but saved `.txt` and `.md` reports are plain text without ANSI color codes.

### Collect recent MDM-related logs

```bash
./mdm-audit.sh --collect-logs
```

This saves a log file next to the main `.txt` and `.md` reports:

```text
reports/mdm-audit-YYYY-mm-dd-HHMMSS.logs.txt
```

The log collection is read-only and uses `log show` predicates for `mdmclient`, `ManagedClient`, `MDM`, and `ConfigurationProfiles` events.

### Verify downloaded files

The `checksums.txt` file contains SHA-256 checksums for release artifacts:

```bash
shasum -a 256 -c checksums.txt
```

### Release pinning

The recommended curl commands use the `v0.1-audit` tag so the downloaded bootstrapper is stable and reviewable. Future changes should use a new tag, for example `v0.2-audit`, with updated checksums.

### Help

```bash
./mdm-audit.sh --help
```

## Interpreting common findings

- **SIP disabled**: high-risk local tampering exposure. Re-enable before production use.
- **Authenticated root disabled**: high-risk system-volume integrity exposure. Re-enable before production use.
- **MDM launchd jobs disabled**: investigate whether MDM services were intentionally or unexpectedly disabled.
- **Profile store locked or unusual flags**: compare against a clean baseline and investigate tampering.
- **MDM enrollment host overrides**: remove unauthorized `/etc/hosts` entries that block Apple enrollment services.

## Hardening checklist

- Keep SIP enabled.
- Keep authenticated root enabled.
- Require FileVault.
- Restrict local administrator rights.
- Monitor MDM enrollment state and profile changes.
- Alert on changes under `/var/db/ConfigurationProfiles`.
- Alert on MDM-related `/etc/hosts` entries.
- Alert when MDM / ManagedClient launchd jobs are disabled.
- Use Automated Device Enrollment where appropriate.
- Maintain a known-good baseline report for comparison.

## Files

- `mdm-audit.sh` — read-only audit and optional log collection tool.
- `mdm-audit-bootstrap.sh` — convenience downloader/runner for `mdm-audit.sh`; verifies the downloaded script with SHA-256 before execution.
- `checksums.txt` — SHA-256 checksums for release verification.
- `reports/` — generated audit reports and optional log collections. Ignored by Git.
- Legacy scripts may exist in the repository for historical coursework context; do not use them on systems without explicit authorization.

## Ethics and scope

This project should be framed around defensive validation: identifying weak local controls, detecting tampering indicators, and recommending administrative hardening steps. Do not run tests against third-party or production systems without written permission.
