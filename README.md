# VITOS

**VIT Operating System for Cybersecurity** — a Kali-based academic security
distro for the VIT Bhopal cybersecurity lab with AI-powered behavioral
monitoring, Firejail-sandboxed pentesting tools, eBPF/auditd telemetry, a
FastAPI+React admin dashboard, WireGuard/Tor Ghost Mode, and FreeIPA SSO.

**Latest release:** [VITOS v1.0.0](https://github.com/crypto0010/VITOS/releases/tag/v1.0.0)
(5 split parts, ~8.5 GB total; see `REASSEMBLE.md` on the release page)

---

## 🎓 Designed and developed at

**Cybersecurity and Digital Forensics Lab**
VIT Bhopal University · Bhopal, Madhya Pradesh, India

| Role | Name |
|---|---|
| Project Director | **Dr. Hemraj Shobharam Lamkuche** — Senior Assistant Professor (Employee ID 100541) |
| Chief Mentor | **Dr. Pon Harshavardhanan** |
| Division Head — Cybersecurity and Digital Forensics | **Dr. Saravanan D.** |

With contributions from **17 team members** listed in [`AUTHORS.md`](AUTHORS.md).

Contact: **vitbhopal.os@gmail.com**

---

## 📦 What's in the box

8 Debian packages on top of a Kali rolling live ISO with a custom hardened
Linux 6.6.52 kernel:

| Package | Role |
|---|---|
| `vitos-base` | Kali base, PAM, sudoers, consent banner, Plymouth theme, VIT Bhopal branding |
| `vitos-tools` | Firejail-wrapped Kali pentest toolchain (metasploit, burp, ghidra, wireshark, aircrack-ng, …) |
| `vitos-monitor` | eBPF + auditd telemetry, AI behavioral engine (Ollama gemma3:4b + scikit-learn Isolation Forest), `vitosctl` CLI |
| `vitos-dashboard` | FastAPI + React admin web console matching the project mockup |
| `vitos-ghost` | WireGuard + Tor network namespace isolation with nftables kill-switch, dual-admin approval via `vitos-ghost-approvers` |
| `vitos-sso` | FreeIPA / LDAP single sign-on, purges v1 hardcoded accounts on join |
| `vitos-hardening` | lynis profile + quarterly debsecan cron + pen-test report template |
| `vitos-vit-bhopal` | 8 lab-exercise scope manifests (recon-101 → capstone-801), retention cron, hostname template |

---

## 📚 Documentation

- **[`AUTHORS.md`](AUTHORS.md)** — team credits
- **[`docs/onboarding/faculty-quickstart.md`](docs/onboarding/faculty-quickstart.md)** — 1-page operator guide for faculty
- **[`docs/deployment/lab-workstation-image.md`](docs/deployment/lab-workstation-image.md)** — per-workstation deployment runbook + pilot bring-up checklist
- **[`docs/security/vitos-pentest-report.md`](docs/security/vitos-pentest-report.md)** — internal pen-test report template
- **[`vitos-v1/README.md`](vitos-v1/README.md)** — build runbook

## 🔬 Research notes

The AI behavioral engine in `vitos-monitor` combines:

- **scikit-learn Isolation Forest** — per-student anomaly model trained on
  the first 3 sessions of normal behavior
- **Ollama gemma3:4b-instruct-q4_K_M** — local LLM for shell-command intent
  classification (BENIGN / RECON / EXPLOIT / EXFIL / LATERAL), served from a
  ~3 GB blob pre-baked into the ISO (zero network calls at first boot)

**Safety rule baked in at the code level:** a `Critical` alert requires
**all three** of: anomaly score > 0.7, malicious-intent label with ≥ 0.6
confidence, and an active lab-scope breach. The LLM alone can never push a
session past `Warning`. All alerts are advisory — no automated punishment.

## 📖 Citation

> Lamkuche, H. S., Harshavardhanan, P., Saravanan, D., et al.
> *VITOS — VIT Cybersecurity Lab Operating System*.
> Cybersecurity and Digital Forensics Lab, VIT Bhopal University, 2026.
> https://github.com/crypto0010/VITOS

## License

See each upstream component's license. Kali Linux, Debian, and every
third-party tool ship under their own licenses.
