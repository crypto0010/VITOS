# VITOS v1 — Integrated Build (Base + Tools + AI Monitoring)

**Date:** 2026-04-07
**Status:** Draft for review (revision 2 — scope expanded per user direction)
**Scope:** Collapses original SP1 (base) + SP2 (sandbox & tools) + SP3 (telemetry) + SP4 (AI engine) into a single shippable v1. SP5 (admin dashboard) and SP6 (ghost mode + pilot hardening) remain separate sub-projects.
**Parent spec:** `main.pdf` (VITOS — academic security distro for VIT cybersecurity labs)

---

## 1. Goal

Produce a bootable, installable Debian 12 (Bookworm) live ISO named **VITOS v1** that a faculty member can hand to a student in a VIT cybersecurity lab and have, on first boot:

1. A working **XFCE desktop** with the academic-integrity consent banner.
2. The full **PDF security toolchain** (Metasploit, Burp, Nmap, Wireshark, Ghidra, Volatility, YARA, etc.) pre-installed and **wrapped in Firejail sandbox profiles**, runnable only by `vitos-students` from within their per-session namespace.
3. **Telemetry collectors** running as systemd services: eBPF (network + exec tree), auditd, fanotify/inotify, bash/zsh history hooks, udev USB logger, dnscrypt query log — all emitting structured JSON to a local event bus.
4. **The AI behavioral engine** running locally, consuming the event bus, scoring risk 0–100, and writing alerts to `/var/log/vitos/alerts.jsonl`. **Ollama is the default LLM runtime**, serving a quantized small model for shell-command intent classification, alongside a scikit-learn Isolation Forest for numeric anomaly detection.
5. A `vitosctl` CLI that lets an `admin` query the alert log and freeze/isolate a student session — the rudimentary stand-in for SP5's full web dashboard.

After v1 ships, the only things still missing from the PDF vision are the **web admin dashboard** (SP5) and the **ghost mode + pilot hardening** layer (SP6).

## 2. Non-goals (explicitly deferred to later sub-projects)

- React + FastAPI **admin web dashboard**, live terminal view, PDF incident reports → **SP5**
- **Ghost mode**: WireGuard/Tor netns, MAC randomizer, dual-approval unlock → **SP6**
- **CVE hardening pass**, internal pen-test of VITOS itself, VIT Bhopal Lab 3 pilot packaging → **SP6**
- **LDAP/FreeIPA university SSO** — v1 ships with the two hardcoded local accounts; SSO joins in SP6
- arm64 build — amd64 only in v1

## 3. Deliverables

1. A `live-build` project tree at `vitos-v1/` producing a hybrid (BIOS+UEFI) live + installable ISO.
2. A custom Debian kernel package `linux-image-vitos-6.6.x` with eBPF / LSM / namespaces / audit / fanotify / cgroup-bpf forced on.
3. Three Debian meta-packages assembled in-tree:
   - **`vitos-base`** — desktop, PAM, consent banner, default users, auditd skeleton.
   - **`vitos-tools`** — every tool from the PDF, each wrapped in a Firejail profile and a `vitos-run` launcher that forces execution inside the student's namespace.
   - **`vitos-monitor`** — telemetry collectors + AI engine + Ollama + `vitosctl`.
4. A pre-baked **Ollama model blob** (`gemma3:4b-instruct-q4_K_M`, ~3.0 GB) shipped inside the ISO at `/var/lib/ollama/models/` so first boot has zero network dependency.
5. Reproducible Docker builder image; three idempotent build scripts (`build-kernel.sh`, `build-iso.sh`, `smoke-test.sh`).
6. **ISO size target: 4.5–5 GB** (Ollama model dominates; XFCE + tools ≈ 1.8 GB; kernel + base ≈ 0.4 GB).
7. **Idle RAM target: ≤ 2 GB** with Ollama loaded; ≤ 1 GB if `ollama serve` is stopped. CLI-only target available for low-RAM lab boxes.
8. **Disk install minimum: 16 GB** (model + tools + room for student work).

## 4. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  VITOS v1 ISO (hybrid live + installer, ~4.7 GB)                │
├─────────────────────────────────────────────────────────────────┤
│  vitosctl (admin CLI: query alerts, freeze/isolate sessions)    │
├─────────────────────────────────────────────────────────────────┤
│  vitos-monitor                                                  │
│  ┌──────────────┐  ┌────────────────┐  ┌─────────────────────┐  │
│  │ Collectors   │─▶│ Event bus      │─▶│ AI engine (Python)  │  │
│  │ • eBPF net   │  │ /run/vitos/bus │  │ • Isolation Forest  │  │
│  │ • eBPF exec  │  │ (UNIX socket + │  │ • Feature extractor │  │
│  │ • auditd     │  │  JSONL ring)   │  │ • Ollama client ──▶ Ollama daemon │
│  │ • fanotify   │  │                │  │   (gemma3:4b q4)    │  (localhost:11434) │
│  │ • inotify    │  │                │  │ • Risk scorer 0–100 │  │
│  │ • bash hooks │  │                │  │ • Alert writer ────▶ /var/log/vitos/ │
│  │ • udev USB   │  │                │  └─────────────────────┘     alerts.jsonl │
│  │ • dnscrypt   │  │                │                             │
│  └──────────────┘  └────────────────┘                             │
├─────────────────────────────────────────────────────────────────┤
│  vitos-tools (each wrapped in Firejail + vitos-run launcher)    │
│  Pentest:  metasploit, nmap, ncat, burpsuite, sqlmap, hydra,    │
│            john, hashcat                                        │
│  Net/Wifi: wireshark, aircrack-ng, ettercap, bettercap, scapy,  │
│            tcpdump                                              │
│  Forensic: autopsy, volatility3, binwalk, ghidra, radare2,      │
│            exiftool, sleuthkit                                  │
│  Malware:  yara, remnux-cli subset, strace, ltrace              │
│  (Cuckoo successor: cape-sandbox planned, gated to admin only)  │
├─────────────────────────────────────────────────────────────────┤
│  vitos-base                                                     │
│  XFCE 4 + LightDM (greeter shows consent banner)                │
│  PAM: pam_faillock + pam_exec consent hook                      │
│  Groups: vitos-students, vitos-admins                           │
│  sudoers.d/vitos: admins=ALL; students=(none)                   │
│  Per-student namespace launcher (PID+net+mount, cgroups v2)     │
├─────────────────────────────────────────────────────────────────┤
│  systemd (audit-hardened) + auditd                              │
├─────────────────────────────────────────────────────────────────┤
│  linux-image-vitos 6.6.x LTS (custom .config)                   │
│   forced-on:  BPF_SYSCALL, BPF_JIT, KPROBES, FANOTIFY,          │
│               SECURITY_SELINUX, SECURITY_APPARMOR,              │
│               USER_NS, PID_NS, NET_NS, MOUNT_NS,                │
│               AUDIT, AUDITSYSCALL, CGROUPS, CGROUP_BPF,         │
│               CGROUP_PIDS, NETFILTER_XT_MATCH_BPF               │
│   forced-off: legacy fs, ISDN, amateur radio, most exotic NICs  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.1 Base distribution

- **Debian 12 Bookworm**, `main` + `contrib` + `non-free-firmware` (firmware needed for lab Wi-Fi/NIC support).
- Built with **`live-build` 1:20230502** from a Bookworm builder container. No third-party repos in SP1.

### 4.2 Desktop

- **XFCE 4.18** — chosen over GNOME (too heavy), KDE (too heavy), i3 (no GUI for non-CLI students), LXQt (smaller community). XFCE gives a familiar Windows-like UX for first-year students, runs well in QEMU, and `task-xfce-desktop` is one apt line.
- **LightDM** as display manager, with a custom greeter background and a pre-login text banner reading the consent notice from §7.
- Default session: XFCE. A `vitos-cli` systemd target is also provided for headless boot (`systemctl isolate vitos-cli.target`) — useful for SP3 testing and for low-spec lab machines.

### 4.3 Kernel

- Source: upstream **linux-stable 6.6.x LTS** (matches Bookworm-backports timeline; LTS until Dec 2026).
- Build: standard Debian kernel packaging (`make bindeb-pkg`) inside the builder container, output `.deb` placed in `vitos-base/config/packages.chroot/`.
- Config strategy: start from `debian/config/amd64/config`, run `make localmodconfig` against a reference QEMU + a reference lab workstation hardware profile, then layer a `vitos.config` fragment that **forces on** every option in the diagram above and **forces off** legacy/unused subsystems. Config fragment is checked into the repo so the kernel is reproducible.
- Module signing enabled; signing key generated at build time and discarded (we are not shipping out-of-tree modules in SP1).
- Single architecture in SP1: **amd64**. arm64 deferred.

### 4.4 User & permission model

Two PAM groups created at first boot by a `vitos-firstboot.service` oneshot:

| Group | Members | Shell | Sudo | Home |
|---|---|---|---|---|
| `vitos-admins` | `admin` (default pw forced-change on first login) | `/bin/bash` | `ALL=(ALL) ALL` | `/home/admin` |
| `vitos-students` | `student` (default pw forced-change on first login) | `/bin/bash` | **none** | `/home/student` |

- `student` has **no sudo entry at all** in SP1. The time-limited token mechanism arrives in SP2.
- `/etc/sudoers.d/vitos` is shipped read-only (mode 0440) and validated with `visudo -c` at build time.
- `pam_faillock` locks an account after 5 failed logins for 15 min (defense against lab password-guessing).
- A `pam_exec` hook runs `/usr/lib/vitos/login-banner` on every login (TTY, SSH, and LightDM via PAM session) which prints/ displays the §7 consent banner and requires the user to type `I AGREE` on first ever login per account (recorded in `/var/lib/vitos/consent.db`, an SQLite file, world-unreadable).

### 4.5 Security toolchain (`vitos-tools`)

Every tool from §"Core Components" of the PDF is installed from Debian + Kali repos (Kali repo pinned to priority 50 so only the explicitly-listed packages get pulled — we don't accidentally inherit all of Kali). Each tool ships with:

1. A **Firejail profile** under `/etc/firejail/vitos-<tool>.profile` — `--noroot`, `--seccomp`, `--caps.drop=all`, network restricted to the lab VLAN by default, filesystem read-only outside the student's session directory.
2. A **`vitos-run` shim** at `/usr/local/bin/<tool>` that:
   - Verifies the caller is in `vitos-students` (admins bypass).
   - Locates or creates the student's per-session namespace via `nsenter`/`unshare` (PID + net + mount + UTS).
   - Tags every emitted event with `student_id`, `session_id`, `tool`, `argv`.
   - `exec`s the real binary inside the namespace under Firejail.
3. A **scope manifest** at `/etc/vitos/lab-scopes/<exercise>.yaml` declaring which tools, target CIDRs, and ports are "in scope" for a given lab exercise. The AI engine reads this to decide whether activity is unethical.

Cuckoo Sandbox is replaced by **CAPEv2** (its actively-maintained successor); CAPE requires KVM and is gated to admin-only in v1 to keep the student attack surface small.

### 4.6 Telemetry collectors (`vitos-monitor`, collector half)

All collectors run as systemd services owned by a dedicated system user `vitos-mon` and write to a single UNIX-domain event bus at `/run/vitos/bus.sock`. The bus is a tiny Go daemon (`vitos-busd`) that fan-outs to:
- A **JSONL ring buffer** at `/var/log/vitos/events.jsonl` (rotated by size, 500 MB cap) — for forensic replay.
- The **AI engine** subscriber (next section).

| Collector | Implementation | Source |
|---|---|---|
| Network flow | eBPF program attached to `tc` ingress/egress, aggregated per (pid, 5-tuple, byte count, packet count) every 1 s | `vitos-bpf-net` |
| Process exec tree | eBPF kprobe on `execve` + `setuid` + `setgid`, parent-child chain reconstructed | `vitos-bpf-exec` |
| File access | `auditd` rules watching sensitive paths (`/etc/{passwd,shadow,sudoers,sudoers.d}`, `/root`, `/home/*/.ssh`, `/var/lib/vitos`) plus a fanotify watcher on `/home/student` | `auditd` + `vitos-fanotify` |
| Command history | bash/zsh `PROMPT_COMMAND` hook + `preexec` writing every command to a per-session FIFO consumed by `vitos-shell-tap` | `/etc/profile.d/vitos-shell-tap.sh` |
| USB/device events | `udevadm monitor --udev` parsed by `vitos-udev-tap` | `vitos-udev-tap` |
| DNS queries | `dnscrypt-proxy` query log shipped via journal | `dnscrypt-proxy` |

Auditd rules under `/etc/audit/rules.d/00-vitos-base.rules` (kept minimal — eBPF carries the heavy lifting):
- Watch `/etc/passwd`, `/etc/shadow`, `/etc/sudoers`, `/etc/sudoers.d/` for write/attribute changes.
- Watch `/var/lib/vitos/consent.db` for any access.
- Log `execve` of UID ≥ 1000 with key `vitos-exec` as a fallback if eBPF is unavailable (e.g., on the GRUB fallback stock kernel).

### 4.7 AI behavioral engine (`vitos-monitor`, AI half)

A Python 3.11 systemd service `vitos-ai.service` running as user `vitos-mon`. Single process, asyncio:

```
event bus subscriber
        │
        ▼
┌──────────────────────────┐
│ Feature extractor        │  rolling 60 s windows per (student, session)
│ • bytes_out, conns_new,  │
│   unique_dst_ips,        │
│   exec_depth, sudo_tries,│
│   sensitive_reads, ...   │
└──────────┬───────────────┘
           ▼
┌──────────────────────────┐      ┌──────────────────────────┐
│ Isolation Forest         │      │ Command intent classifier│
│ (scikit-learn, baselined │      │ Ollama HTTP @ 11434      │
│  on first 3 sessions per │      │ Model: gemma3:4b-instruct│
│  student)                │      │  -q4_K_M  (~3.0 GB)      │
│ → numeric anomaly score  │      │ Prompt: "Classify this   │
│   0.0–1.0                │      │  shell command as        │
└──────────┬───────────────┘      │  BENIGN / RECON /        │
           │                      │  EXPLOIT / EXFIL /        │
           │   ┌──────────────────┤  LATERAL with reason."   │
           │   │                  │ → label + confidence     │
           ▼   ▼                  └──────────────────────────┘
┌──────────────────────────┐
│ Composite risk scorer    │  weighted blend, clamped 0–100
│ score = 60·anomaly       │
│       + 30·intent_risk   │
│       + 10·scope_breach  │
└──────────┬───────────────┘
           ▼
┌──────────────────────────┐
│ Alert writer             │  → /var/log/vitos/alerts.jsonl
│ Categories:              │     {ts, student, session, score,
│  🟡 Suspicious  20–49    │      category, signals, ai_reason}
│  🟠 Warning     50–79    │
│  🔴 Critical    80–100   │
│ Critical → vitos-busd    │
│   broadcasts "isolate"   │
│   event; vitos-isolated  │
│   service nukes the      │
│   student's net ns       │
└──────────────────────────┘
```

**Why Ollama as default:** user direction. Ollama is a one-binary local LLM server with a stable HTTP API, model auto-loading, and `systemctl`-friendly lifecycle. The model file is shipped *inside* the ISO at `/var/lib/ollama/models/blobs/` and registered via `ollama create vitos-intent -f /etc/vitos/Modelfile` during firstboot, so v1 has **zero network calls** to pull a model. Ollama is started via `ollama.service` (systemd unit shipped in the package). The `vitos-ai` service connects to `http://127.0.0.1:11434` and degrades gracefully (intent score = 0, anomaly-only) if Ollama is unreachable or `vitos-ai-lite` mode is set in `/etc/vitos/ai.toml` for low-RAM machines.

**Model choice — `gemma3:4b-instruct-q4_K_M`:**
- ~3.0 GB on disk, ~3.5 GB resident — fits the 4–5 GB ISO budget and a 6 GB student VM.
- Strong instruction-following for short shell-command classification.
- Apache-2.0 friendly redistribution terms suitable for an academic distro.
- Swappable: `/etc/vitos/ai.toml` exposes `model = "..."`; admin can switch to `phi3:mini`, `qwen2.5:3b`, etc. with `ollama pull` (network required).

**Baseline learning:** the first 3 sessions per `student_id` are tagged `baseline=true` and the Isolation Forest is refit nightly via `vitos-ai-train.timer`. Until 3 baseline sessions exist, anomaly score is fixed at 0 (engine is in "learning" mode and only intent + scope breach can trigger alerts).

**Privacy / safeguards (binding for v1):** all alerts are **advisory**; only `category=Critical` triggers the automatic network-namespace isolation, and even that only severs the student's network — it never kills processes, never wipes data, and is fully logged. No model inference data leaves the box.

### 4.8 `vitosctl` admin CLI

A Python Click app installed setuid-via-sudoers for `vitos-admins`. Subcommands in v1:

- `vitosctl status` — services up, model loaded, event rate, top-5 students by risk.
- `vitosctl alerts [--since 1h] [--min-score 50]` — tail/filter `alerts.jsonl`.
- `vitosctl session list` — active student sessions.
- `vitosctl session freeze <session_id>` — sends `SIGSTOP` to the namespace's PID 1 (resumable).
- `vitosctl session isolate <session_id>` — drops the namespace's veth.
- `vitosctl scope load <exercise.yaml>` — activate a lab-exercise scope manifest.
- `vitosctl report <student_id>` — render a Markdown incident summary (PDF rendering deferred to SP5).

This CLI is the **temporary stand-in** for the SP5 web dashboard. It is intentionally minimal so SP5 can replace it without users depending on a half-built web UI in the meantime.

### 4.9 Filesystem layout & ISO mode

- **Live mode:** SquashFS root + tmpfs overlay (live-build default). Useful for demo USB sticks; no persistent state.
- **Installed mode:** the same SquashFS is copied to disk by `calamares` (Debian's standard graphical installer, themed with a VITOS background) onto an ext4 root + 1 GB swap. LUKS optional in the installer (off by default in SP1 — enabled by default in SP6 hardening).
- `/var/lib/vitos/` is created on first boot and is the canonical location for all VITOS-specific state (consent DB now; SP3 collectors and SP4 models later).

### 4.10 Build pipeline

```
┌────────────┐   docker build    ┌──────────────────┐
│ Dockerfile │ ────────────────► │ vitos-builder    │
└────────────┘                   │ (Debian 12 +     │
                                 │  live-build,     │
                                 │  kernel deps)    │
                                 └────────┬─────────┘
                                          │ docker run -v repo:/build
                                          ▼
                ┌──────────────────────────────────────┐
                │ /build/scripts/build-kernel.sh       │
                │   → linux-image-vitos_6.6.x_amd64.deb│
                │ /build/scripts/build-iso.sh          │
                │   → vitos-base-YYYYMMDD-amd64.iso    │
                │ /build/scripts/smoke-test.sh         │
                │   → boots ISO in QEMU, runs asserts  │
                └──────────────────────────────────────┘
```

All three scripts are idempotent and runnable individually. CI (out of scope for SP1, noted for SP6) will eventually invoke them in order.

## 5. Repository layout

```
vitos/
├── docs/superpowers/specs/2026-04-07-vitos-sp1-base-iso-design.md   ← this file
├── vitos-v1/
│   ├── Dockerfile                          # vitos-builder image
│   ├── kernel/
│   │   ├── vitos.config                    # forced y/n fragment
│   │   └── build-kernel.sh
│   ├── packages/
│   │   ├── vitos-base/                     # debian/ source pkg
│   │   ├── vitos-tools/                    # firejail profiles + vitos-run shims
│   │   └── vitos-monitor/                  # collectors + AI engine + vitosctl
│   │       ├── busd/                       # Go: vitos-busd
│   │       ├── bpf/                        # eBPF C: net + exec collectors
│   │       ├── ai/                         # Python: feature ext, IF, ollama client
│   │       ├── cli/                        # Python: vitosctl
│   │       └── systemd/                    # *.service, *.timer units
│   ├── ollama-blob/
│   │   ├── Modelfile                       # registers gemma3:4b at firstboot
│   │   └── fetch-model.sh                  # builder-time model download
│   ├── live-build/
│   │   ├── auto/config
│   │   ├── config/
│   │   │   ├── package-lists/vitos.list.chroot
│   │   │   ├── packages.chroot/            # custom .debs land here
│   │   │   ├── archives/kali.list.chroot   # pinned Kali repo (priority 50)
│   │   │   ├── includes.chroot/            # /etc, /usr/lib/vitos, banners, units
│   │   │   └── hooks/normal/9000-firstboot.hook.chroot
│   │   └── build-iso.sh
│   └── tests/
│       ├── smoke-test.sh                   # QEMU boot + §6 assertions
│       └── ai-replay/                      # canned event traces for AI unit tests
└── README.md
```

## 6. Smoke-test assertions (v1 "done" definition)

The QEMU smoke test boots the ISO with `-m 6144 -smp 4 -enable-kvm -nographic` and asserts:

**Base layer**
1. `uname -a` reports `Linux 6.6.* vitos`.
2. `zgrep -E 'CONFIG_(BPF_SYSCALL|USER_NS|AUDIT|FANOTIFY|CGROUP_BPF)=y' /proc/config.gz` — all present.
3. `getent group vitos-students vitos-admins` returns both.
4. `sudo -l -U student` shows nothing; `sudo -l -U admin` shows `(ALL) ALL`.
5. Consent banner text from §7 appears on TTY1 and in the LightDM greeter.
6. ISO size between **4.0 GB and 5.0 GB**.
7. Idle RAM 60 s after XFCE login with Ollama running ≤ **2048 MB**.

**Tools layer**
8. `which msfconsole nmap wireshark ghidra volatility3 yara burpsuite` all resolve to `/usr/local/bin/` shims.
9. As `student`, `nmap -sS 10.0.0.1` runs **inside** Firejail (verified by `firejail --list` showing the process) and is restricted to the lab VLAN (an out-of-scope target returns "operation not permitted").
10. As `admin`, the same command runs unrestricted.

**Telemetry layer**
11. `systemctl is-active vitos-busd vitos-bpf-net vitos-bpf-exec vitos-shell-tap vitos-udev-tap auditd` — all `active`.
12. After running `nmap -sS 10.0.0.1` as `student`, a corresponding event appears in `/var/log/vitos/events.jsonl` within 2 s, tagged with the student session ID.

**AI layer**
13. `systemctl is-active ollama vitos-ai` — both `active`.
14. `curl -s http://127.0.0.1:11434/api/tags` lists the `vitos-intent` model (sourced from the pre-baked blob, **no network call made during firstboot** — verified by booting with `-net none`).
15. Replaying a canned "recon" event trace from `tests/ai-replay/recon.jsonl` into the bus produces an alert in `/var/log/vitos/alerts.jsonl` within 5 s with `category` ∈ {`Warning`,`Critical`} and a non-empty `ai_reason` field from the LLM.
16. `vitosctl alerts --since 1m` displays that alert.
17. `vitosctl session isolate <id>` severs the namespace's network within 1 s (verified by `ip netns exec` ping failing).

If all 17 pass, v1 is shippable to SP5.

## 7. Consent banner (verbatim)

> **VITOS — VIT Cybersecurity Lab Operating System**
>
> This system is operated by VIT for academic instruction in cybersecurity. By logging in you acknowledge that your activity on this system — including network traffic, executed commands, file access, and connected devices — is monitored and recorded for the purposes of academic integrity, lab safety, and student assessment, in accordance with VIT policy and applicable data protection law (FERPA / India DPDP Act 2023).
>
> Monitoring data is accessible only to authorized faculty. Any actions taken in response to monitoring are advisory and subject to human review.
>
> Type **I AGREE** to continue, or log out now.

This text is the legal anchor for everything SP3–SP5 will collect. It is reviewed once here and then frozen for the lifetime of SP1; later sub-projects must not weaken or contradict it.

## 8. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Custom kernel breaks on real lab hardware | `make localmodconfig` against a reference workstation; keep `non-free-firmware`; ship the stock Debian kernel as a GRUB fallback entry. |
| ISO blows past 5 GB | Ollama model is the dominant cost (~3 GB). If over budget: drop `xfce4-goodies`/LibreOffice/GIMP, drop Ghidra (~400 MB) to a post-install opt-in, and/or downshift the model from `gemma3:4b-q4` to `gemma3:1b-q4` (~0.8 GB) at the cost of intent-classification quality. |
| Ollama RAM footprint pushes lab boxes over budget | `vitos-ai-lite` mode in `/etc/vitos/ai.toml` disables LLM intent classification and falls back to anomaly-only scoring. CLI-only target avoids XFCE's ~400 MB. |
| Kali repo pin leaks unwanted packages | apt pin priority 50 + explicit allowlist in `package-lists/vitos.list.chroot`; `apt-cache policy` checked in CI. |
| eBPF programs fail to load on the GRUB fallback stock kernel | auditd `execve` rule from §4.6 carries the bare minimum signal until the user reboots into the VITOS kernel. The AI engine logs a degraded-mode warning. |
| LLM hallucinates a critical alert and isolates a benign student | Critical-tier requires **both** anomaly_score > 0.7 **and** intent_label ∈ {EXPLOIT, EXFIL, LATERAL} **and** scope_breach=true. LLM alone can never push past Warning. All isolations are reversible via `vitosctl session isolate --revert`. |
| Pre-baked model file makes ISO non-reproducible | `fetch-model.sh` records the model SHA256 in `ollama-blob/SHA256SUMS`; build fails if the downloaded blob doesn't match. |
| `live-build` is mostly unmaintained upstream | Acceptable for v1 (works on Bookworm). SP6 re-evaluates `mkosi`. |
| First-boot consent flow blocks automation/CI | Kernel cmdline `vitos.consent=preaccepted` skips the interactive prompt; only honored inside the test container, never on shipped ISOs. |
| Two hardcoded default accounts are a security smell | Acceptable in v1; SP6 deletes both on FreeIPA join. Loudly documented in the README. |
| AI engine becomes a covert surveillance tool | Hard rules baked into v1: alerts are advisory, model runs locally with no network egress, all alerts are tagged with the rules that fired so a human reviewer can audit, and the consent banner in §7 is the legal anchor. |

## 9. Sub-projects still to come after v1

- **SP5** — React + FastAPI admin dashboard replacing `vitosctl`, live terminal view via gotty/tmux, PDF incident report generation, network map visualization.
- **SP6** — Ghost mode (WireGuard/Tor netns, MAC randomizer, kill-switch, dual-approval), LDAP/FreeIPA join + delete-default-accounts, CVE hardening pass, internal pen-test of VITOS itself, FERPA/DPDP retention policy automation, VIT Bhopal Lab 3 pilot packaging.
