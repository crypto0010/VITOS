# VITOS SP6 — Ghost Mode, FreeIPA SSO, CVE Hardening, VIT Pilot

**Date:** 2026-04-08
**Status:** Draft for review
**Sub-project:** SP6 of 6 (final sub-project — closes out the VITOS roadmap)
**Parent specs:**
  - `2026-04-07-vitos-sp1-base-iso-design.md` (VITOS v1, shipped)
  - `2026-04-08-vitos-sp5-admin-dashboard-design.md` (SP5, in flight)

---

## 1. Goal

Land four independent capability bundles that together turn VITOS from "works in CI" into "deployable to a real VIT Bhopal cybersecurity lab":

1. **Ghost Mode** for authorized faculty / PhD researchers — WireGuard + Tor netns isolation, MAC randomization, nftables kill-switch, DNS-over-HTTPS, hostname randomization. Available **only** under dual-admin unlock; all activity is still logged internally even when the external trace is hidden.
2. **FreeIPA / LDAP SSO** — students and faculty authenticate against the university directory; the hardcoded `admin`/`student` accounts shipped in v1 are deleted on first successful join.
3. **CVE hardening pass + internal pen-test of VITOS itself** — debsecan + lynis + a manual review pass on every custom component (vitos-busd, vitos-ai, vitosctl, vitos-dashboard).
4. **VIT Bhopal Lab 3 pilot packaging** — site-customisation hooks (hostname, lab-scope manifests, university branding overlay), unattended installer profile for lab workstation deployment via PXE/USB, FERPA / India DPDP retention policy automation, faculty onboarding doc.

After SP6 ships, the VITOS roadmap from `main.pdf` is fully implemented.

## 2. Non-goals

- New tools, new AI models, new collectors. The functionality from v1 is frozen.
- Cross-lab federation. Single lab per install.
- Mobile / cloud / SaaS. Bare metal (or KVM) lab workstations only.
- Replacing live-build with mkosi (was a v1 follow-up note; defer indefinitely).

## 3. Deliverables

| # | Deliverable | Package / location |
|---|---|---|
| 1 | `vitos-ghost` Debian package (WireGuard config, Tor netns scripts, nftables kill-switch, dual-approval daemon, MAC randomizer udev rules) | `vitos-v1/packages/vitos-ghost/` |
| 2 | `vitos-sso` Debian package (FreeIPA join automation, PAM/SSSD config, default-account purge hook, LDAP backend for `vitos-dashboard`) | `vitos-v1/packages/vitos-sso/` |
| 3 | `vitos-hardening` meta-package + audit reports (debsecan run, lynis profile, custom-component pen-test report) | `vitos-v1/packages/vitos-hardening/` + `docs/security/vitos-pentest-report.md` |
| 4 | `vitos-vit-bhopal` site overlay package (hostname template, lab-scope manifests for the 8 standard cybersec lab exercises, VIT branding swap, FERPA retention cron) | `vitos-v1/packages/vitos-vit-bhopal/` |
| 5 | **Unattended installer profile** for the live ISO (`auto-install.cfg` + preseed) so PXE/USB deploys onto a lab workstation with zero clicks | `vitos-v1/live-build/config/includes.installer/` |
| 6 | **Faculty onboarding guide** — 1-page Markdown explaining how to enable Ghost Mode, manage scopes, read alerts, run incident reports | `docs/onboarding/faculty-quickstart.md` |
| 7 | **Smoke test extensions** (8 new assertions, total now 29) covering ghost mode toggling, FreeIPA join, kill-switch effectiveness, default-account deletion, and unattended installer reach | `vitos-v1/tests/smoke-test.sh` |

## 4. Architecture

### 4.1 Ghost Mode

```
                       admin runs:  vitosctl ghost enable <user>
                                              │
                       (dual-admin approval check)
                                              │
                       ▼
┌──────────────────────────────────────────────────────────────┐
│ /etc/vitos/ghost/profiles/<user>.conf  (created on enable)   │
└──────────────┬───────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────┐    ┌────────────────────────────┐
│ ip netns add ghost-<uid>    │    │ macchanger -r eth0          │
│ ip link set veth0 netns ... │    │ hostname (random word list) │
│ run wg-quick up wg-vitos    │    │ /etc/timezone overwrite     │
│ run torify proxy chain      │    │                             │
│ nft kill-switch:            │    │                             │
│   drop all !lo !wg !tor     │    │                             │
└──────────────┬──────────────┘    └─────────────────────────────┘
               │
               ▼
        user shell launched inside netns
               │
               ▼
┌──────────────────────────────────────────────────────────────┐
│ Internal logging continues normally — vitos-busd events are  │
│ still emitted from inside the netns via a UNIX-socket bind   │
│ mount. Ghost Mode hides the *external* trace, not the        │
│ academic-integrity audit trail.                              │
└──────────────────────────────────────────────────────────────┘
```

**Dual-admin approval:** `vitosctl ghost enable` writes a pending request to `/var/lib/vitos/ghost/pending/<id>.req`. A second admin must run `vitosctl ghost approve <id>`. Only then is `/etc/vitos/ghost/profiles/<user>.conf` written.

**Kill-switch:** nftables ruleset shipped at `/etc/nftables.d/vitos-ghost.nft`. Loaded by `vitos-ghost-killswitch.service` which monitors WireGuard handshake state via `wg show` polling every 2 s and drops all non-tunnel traffic if the tunnel hasn't seen a handshake in 30 s.

**Tor routing (Whonix-style):** the netns has a single default route to a SOCKS5 proxy on `127.0.0.1:9050` (Tor) inside the same netns. All TCP traffic is transparently redirected via `nft tproxy`. UDP is dropped (Tor doesn't carry UDP).

### 4.2 FreeIPA SSO

`vitos-sso` postinst:

1. Prompts for FreeIPA realm + admin credentials (or reads `/etc/vitos/sso.toml` for unattended installs).
2. Runs `ipa-client-install --unattended --domain=… --principal=… --password=…`.
3. Configures SSSD with `services = nss, pam` and `id_provider = ipa`.
4. Replaces `/etc/pam.d/common-auth` to chain `pam_sss` before `pam_unix`.
5. Deletes the hardcoded `admin` and `student` users created by `vitos-firstboot.service`.
6. Updates `vitos-dashboard`'s `auth.py` to use the new LDAP/SSSD path.
7. Triggers `vitos-dashboard.service` restart.

### 4.3 CVE hardening + pen-test

Three reports, all checked into `docs/security/`:

| Report | Tool | Schedule |
|---|---|---|
| `vitos-cve-baseline.md` | `debsecan --suite kali-rolling --format detail` | quarterly via cron |
| `vitos-lynis.txt` | `lynis audit system --profile vitos.prf` | quarterly |
| `vitos-pentest-report.md` | manual review of vitos-busd, vitos-ai, vitosctl, vitos-dashboard, vitos-ghost — code + threat-model + dependency audit | one-shot, before pilot |

The `vitos-hardening` meta-package only ships the lynis profile, the cron entry, and the report templates — the *content* lives in `docs/security/`.

### 4.4 VIT Bhopal site overlay

`vitos-vit-bhopal` ships:

- `/etc/hostname.template` — `vitos-bhopal-lab3-{NN}` where `{NN}` is filled by `vitos-firstboot.sh` using a MAC-derived hash.
- `/etc/vitos/lab-scopes/{recon-101,exploit-201,forensics-301,malware-401,wireless-501,web-601,mobile-701,capstone-801}.yaml` — the 8 standard cybersec lab manifests for the VIT semester.
- `/usr/share/vitos/branding/vit-bhopal-logo.png` — replaces v1's generic logo (already done in v1, but locked here).
- `/etc/cron.d/vitos-retention` — runs daily, removes `events.jsonl` rows older than 180 days and `alerts.jsonl` rows older than 365 days, configurable in `/etc/vitos/retention.toml`. Compliance anchor is FERPA + India DPDP Act 2023.

### 4.5 Unattended installer

A `/preseed.cfg` shipped at `live-build/config/includes.installer/preseed.cfg` plus a `live-build` rebuild with `--debian-installer cdrom` enabled, so the same ISO can also boot the standard Debian/Kali installer for permanent disk install.

Preseed answers: en_US locale, lab VLAN DHCP, ext4 + LUKS root, install all VITOS meta-packages, run `vitos-sso` join from `/etc/vitos/sso.toml` shipped on a USB key, reboot.

USB-key staging procedure documented in `docs/deployment/lab-workstation-image.md`.

## 5. Smoke-test extensions (29 total)

8 new assertions on top of v1's 17 + SP5's 4:

```
say "ghost_disabled_by_default=PASS" if ! ip netns list | grep -q ghost-
say "ghost_dual_approval=PASS" if vitosctl ghost enable test 2>&1 | grep -q "pending"
say "killswitch_blocks_when_tunnel_down=PASS" if ! ip netns exec ghost-1000 ping -W2 8.8.8.8
say "freeipa_default_accounts_purged=PASS" if ! id admin && ! id student && id $TESTUSER
say "sssd_active=PASS" if systemctl is-active --quiet sssd
say "lynis_score_above_70=PASS" if [ "$(lynis audit system --quick --no-colors | awk '/Hardening index/ {print $4}')" -gt 70 ]
say "retention_cron=PASS" if [ -f /etc/cron.d/vitos-retention ]
say "vit_branding=PASS" if grep -q 'VIT Bhopal' /usr/share/vitos/branding/banner-ascii.txt
```

## 6. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Ghost mode is dual-use — could be abused by a rogue admin | Dual-admin approval requirement is a hard rule. Audit log entries for every enable/approve/disable. Spec-level prohibition on disabling internal logging from inside ghost mode. |
| FreeIPA join fails on a fresh lab without existing IPA server | The package supports `--no-server` mode where SSO is staged but not activated. Fail-soft: hardcoded accounts remain until `ipa-client-install` succeeds. |
| Pen-test surfaces fundamental flaws in v1 (e.g. eBPF privilege escape) | SP6 explicitly schedules a "fix forward in v1" budget. Critical findings block the pilot. |
| FERPA / DPDP retention timer accidentally deletes a live investigation | Retention cron honors `/etc/vitos/retention.hold` lock files; admin can pin a student's logs by `touch`-ing the lock. |
| Unattended installer sets a default LUKS passphrase | Preseed reads passphrase from a USB-key file (not baked into ISO). Documented loudly. |
| Kali rolling drift between pilot ISO build and lab deploy | The shipped ISO is self-contained — debootstrap doesn't run at install time. Lab workstations boot the exact frozen ISO contents. |

## 7. Open questions for the user (answer before plan-writing)

These need a one-line answer each before I can write the implementation plan:

1. **Tor or i2p?** PDF says Tor. Confirming Tor + Tor Browser are the targets, and i2p is out of scope for SP6.
2. **FreeIPA realm name** for VIT Bhopal? E.g. `LAB.VIT-BHOPAL.AC.IN`. If not known yet, we'll plumb a config placeholder.
3. **Lab VLAN CIDR?** The Firejail profiles in v1 hardcoded `10.10.0.0/16` as a placeholder. SP6 should swap this for the real lab subnet.
4. **Dual-admin approval implementation:** require two distinct `vitos-admins` group members, or a separate `vitos-ghost-approvers` group? Default: two distinct admins.
5. **Lab exercise count** — I assumed 8 standard exercises (recon, exploit, forensics, malware, wireless, web, mobile, capstone). Confirm or substitute the real VIT Bhopal cybersec semester syllabus.

## 8. Sub-project ordering inside SP6

SP6 itself decomposes into 4 independent tracks that can be built in parallel by different engineers, then integrated at the end:

| Track | Owner | Depends on | Output |
|---|---|---|---|
| 6A — Ghost Mode | A | none | `vitos-ghost` package |
| 6B — FreeIPA SSO | B | none | `vitos-sso` package |
| 6C — Hardening | C | 6A + 6B (audits the new code) | reports + `vitos-hardening` |
| 6D — VIT pilot | D | 6A + 6B + 6C | `vitos-vit-bhopal` + installer + onboarding doc |

Final integration = one big release.yml run that builds all four packages into the same ISO and ships **VITOS v1.0** (the academic-integrity release tag).
