# macOS MDM Student Security Project

This repository is being used for a white-hat student project focused on macOS MDM security posture, detection, and hardening.

> Use only on devices you own or are explicitly authorized to assess.

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

```bash
./mdm-audit.sh
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
- `reports/` — generated audit reports and optional log collections. Ignored by Git.
- Legacy scripts may exist in the repository for historical coursework context; do not use them on systems without explicit authorization.

## Ethics and scope

This project should be framed around defensive validation: identifying weak local controls, detecting tampering indicators, and recommending administrative hardening steps. Do not run tests against third-party or production systems without written permission.
