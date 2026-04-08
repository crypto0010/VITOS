# VITOS SP6 Implementation Plan — Ghost Mode + SSO + Hardening + Pilot

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add the four final capability bundles needed for VITOS to be deployable in a real VIT Bhopal cybersecurity lab: WireGuard/Tor Ghost Mode (dual-admin gated), FreeIPA SSO replacing the v1 hardcoded accounts, CVE/lynis hardening pass + internal pen-test, and the VIT site-overlay package + unattended installer.

**Architecture:** Four independent Debian source packages (`vitos-ghost`, `vitos-sso`, `vitos-hardening`, `vitos-vit-bhopal`) plus an unattended-installer profile for the live ISO. Each package is built into the v1 ISO via the existing live-build pipeline. Smoke test grows from 21 to 29 assertions.

**Tech Stack:** WireGuard, Tor, nftables, macchanger, dnscrypt-proxy, FreeIPA client, SSSD, debsecan, lynis, Debian preseed.

**Spec:** `docs/superpowers/specs/2026-04-08-vitos-sp6-ghost-mode-hardening-pilot-design.md`

**Tracks:** SP6 splits into 4 parallel tracks. The plan below lists tasks per track; tracks 6A and 6B can run in parallel, 6C waits for both, 6D waits for 6C.

---

## Track 6A — Ghost Mode

### Task 6A.1 — vitos-ghost package skeleton
- [ ] Create `vitos-v1/packages/vitos-ghost/debian/{control,rules,changelog,install,postinst}`
- [ ] Depends: `wireguard, tor, nftables, macchanger, dnscrypt-proxy, jq`
- [ ] Commit

### Task 6A.2 — Network namespace + WireGuard launcher
- [ ] Write `/usr/lib/vitos/ghost/launch.sh` that creates `ghost-<uid>` netns, moves `veth0` in, runs `wg-quick up wg-vitos` inside
- [ ] Tor config staged at `/etc/vitos/ghost/torrc.template`; rendered into the netns at launch
- [ ] Commit

### Task 6A.3 — nftables kill-switch
- [ ] Ship `/etc/nftables.d/vitos-ghost.nft` (drop all but lo + wg0 + tor)
- [ ] Watchdog systemd unit `vitos-ghost-killswitch@.service` polls `wg show` every 2 s
- [ ] Commit

### Task 6A.4 — Dual-admin approval daemon
- [ ] Extend `vitosctl` with `ghost enable|approve|disable|list` subcommands
- [ ] Pending requests in `/var/lib/vitos/ghost/pending/<id>.req`; approval moves to `/var/lib/vitos/ghost/active/`
- [ ] Audit log entries for every state change
- [ ] Commit

### Task 6A.5 — MAC randomization udev rule
- [ ] Ship `/etc/udev/rules.d/80-vitos-mac-randomize.rules`
- [ ] Triggered by `vitos.ghost=1` boot flag, runs `macchanger -r` on every interface
- [ ] Commit

### Task 6A.6 — Tests
- [ ] Unit: bash test asserting `vitosctl ghost enable` writes to `pending/`, `approve` moves to `active/`
- [ ] Integration: in CI, simulate enable+approve+launch (no real Tor) and verify `ip netns list` shows the new ns
- [ ] Commit

---

## Track 6B — FreeIPA SSO

### Task 6B.1 — vitos-sso package skeleton
- [ ] Create `vitos-v1/packages/vitos-sso/debian/{control,rules,changelog,install,postinst}`
- [ ] Depends: `freeipa-client, sssd, sssd-ipa, libpam-sss, libnss-sss`
- [ ] Commit

### Task 6B.2 — Join automation
- [ ] Write `/usr/lib/vitos/sso/join.sh` that reads `/etc/vitos/sso.toml` and runs `ipa-client-install --unattended`
- [ ] Fail-soft: if no `sso.toml` or join fails, leave hardcoded accounts in place
- [ ] Commit

### Task 6B.3 — PAM/SSSD wiring
- [ ] postinst replaces `/etc/pam.d/common-auth` to chain `pam_sss` before `pam_unix`
- [ ] Configures SSSD with `services = nss, pam` and `id_provider = ipa`
- [ ] Commit

### Task 6B.4 — Default-account purge
- [ ] On successful first join, delete the v1-hardcoded `admin` and `student` users
- [ ] Move their home dirs to `/var/lib/vitos/legacy-homes/` (don't destroy data)
- [ ] Commit

### Task 6B.5 — vitos-dashboard LDAP backend
- [ ] Extend `vitos-dashboard` `auth.py` to try SSSD/LDAP first, PAM second
- [ ] Restart dashboard service in postinst
- [ ] Commit

---

## Track 6C — CVE Hardening + Pen-test

### Task 6C.1 — debsecan baseline
- [ ] Run inside CI: `debsecan --suite kali-rolling --format detail > docs/security/vitos-cve-baseline.md`
- [ ] Commit the report
- [ ] Add a quarterly cron entry shipped via `vitos-hardening`

### Task 6C.2 — lynis profile + run
- [ ] Write `lynis.prf` with VITOS-specific overrides
- [ ] Run `lynis audit system --profile vitos.prf > docs/security/vitos-lynis.txt`
- [ ] Target hardening index ≥ 70
- [ ] Commit

### Task 6C.3 — Manual pen-test of custom components
- [ ] Threat model + code review of `vitos-busd` (Go), `vitos-ai` (Python), `vitosctl`, `vitos-dashboard`, `vitos-ghost`
- [ ] Test: can a `vitos-students` user escape Firejail? Read another student's `events.jsonl`? Tamper with `consent.db`?
- [ ] Write findings to `docs/security/vitos-pentest-report.md`
- [ ] Fix every Critical and High in v1 source before SP6 release
- [ ] Commit

### Task 6C.4 — vitos-hardening package
- [ ] Ships only the lynis profile, the cron entry, and report templates
- [ ] All actual reports live in `docs/security/`
- [ ] Commit

---

## Track 6D — VIT Bhopal Pilot

### Task 6D.1 — vitos-vit-bhopal package skeleton
- [ ] Create `vitos-v1/packages/vitos-vit-bhopal/debian/{control,rules,changelog,install,postinst}`
- [ ] Commit

### Task 6D.2 — Hostname template + lab-scope manifests
- [ ] `/etc/hostname.template` rendered to `vitos-bhopal-lab3-{NN}` at firstboot
- [ ] Ship 8 lab-scope YAML files (recon-101 through capstone-801)
- [ ] Commit

### Task 6D.3 — FERPA / DPDP retention cron
- [ ] `/etc/cron.d/vitos-retention` runs daily, reads `/etc/vitos/retention.toml`
- [ ] Default: 180 d events, 365 d alerts; honors `retention.hold` lockfiles
- [ ] Commit

### Task 6D.4 — Branding lock
- [ ] vitos-vit-bhopal owns `/usr/share/vitos/branding/vit-bhopal-logo.png`
- [ ] Conflicts with any third-party branding overlay
- [ ] Commit

### Task 6D.5 — Unattended installer profile
- [ ] Add `live-build/config/includes.installer/preseed.cfg`
- [ ] Re-enable `--debian-installer cdrom` in `auto/config`
- [ ] Document USB-key staging in `docs/deployment/lab-workstation-image.md`
- [ ] Commit

### Task 6D.6 — Faculty onboarding doc
- [ ] Write `docs/onboarding/faculty-quickstart.md` (1 page)
- [ ] Cover: ghost mode enable, scope activation, alert review, incident report PDF
- [ ] Commit

---

## Final integration

### Task 6.99 — Ship VITOS v1.0
- [ ] All four packages in the `release.yml` matrix
- [ ] Smoke test = 29 assertions
- [ ] Run release workflow
- [ ] Tag `v1.0.0` (drop the 0.0.0-* dev tags)
- [ ] Update `docs/onboarding/faculty-quickstart.md` with the v1.0.0 download URL

---

## Open questions (must answer before execution starts)

1. Tor or i2p? (default: Tor)
2. FreeIPA realm name for VIT Bhopal?
3. Lab VLAN CIDR (currently `10.10.0.0/16` placeholder)?
4. Dual-admin = two `vitos-admins` members or a separate `vitos-ghost-approvers` group? (default: two distinct admins)
5. Real lab exercise list — confirm 8 standard exercises or substitute the actual VIT Bhopal cybersec semester syllabus.
