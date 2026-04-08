# VITOS v1

Kali-based academic security distro for the VIT Bhopal cybersecurity lab with
AI-powered behavioral monitoring (Ollama + Isolation Forest), Firejail-sandboxed
pentesting tools, eBPF/auditd telemetry, a FastAPI+React admin dashboard,
WireGuard/Tor Ghost Mode with dual-admin gating, and FreeIPA SSO.

**Designed and developed at the Cybersecurity and Digital Forensics Lab, VIT
Bhopal University.** See [`../AUTHORS.md`](../AUTHORS.md) for the full team.

- Project Director: **Dr. Hemraj Shobharam Lamkuche** — `vitbhopal.os@gmail.com`
- Chief Mentor: **Dr. Pon Harshavardhanan**
- Division Head, Cybersecurity and Digital Forensics: **Dr. Saravanan D.**

Specs: [`../docs/superpowers/specs/`](../docs/superpowers/specs/)
Plans: [`../docs/superpowers/plans/`](../docs/superpowers/plans/)
Released ISO: https://github.com/crypto0010/VITOS/releases

## Build

Requires a Linux build host (or Windows + Docker Desktop with WSL2) with
`/dev/kvm` available.

```bash
docker build -t vitos-builder vitos-v1/

# 1. Kernel (~30 min first time)
docker run --rm -v "$PWD:/build" vitos-builder \
  -c '/build/vitos-v1/kernel/build-kernel.sh'

# 2. Each Debian package
for pkg in vitos-base vitos-tools vitos-monitor vitos-dashboard \
           vitos-ghost vitos-sso vitos-hardening vitos-vit-bhopal; do
  docker run --rm -v "$PWD:/build" vitos-builder -c \
    "cd /build/vitos-v1/packages/$pkg && dpkg-buildpackage -us -uc -b && \
     mv ../${pkg}_*.deb /build/vitos-v1/live-build/config/packages.chroot/"
done

# 3. ISO (~60 min first time, includes ~3 GB Ollama model download)
docker run --rm --privileged -v "$PWD:/build" vitos-builder \
  -c '/build/vitos-v1/live-build/build-iso.sh'

# 4. Smoke test
docker run --rm --privileged --device /dev/kvm -v "$PWD:/build" vitos-builder \
  -c '/build/vitos-v1/tests/smoke-test.sh'
```

Output: `vitos-v1/vitos-v1-YYYYMMDD-amd64.iso` (~8.5 GB).

## Default credentials (CHANGE IMMEDIATELY)

- `admin` / `changeme` — full sudo
- `student` / `changeme` — sandboxed, no sudo

Both accounts are forced to change password on first login. `vitos-sso` replaces
them with FreeIPA on a successful realm join.

## Layers

| Layer | Package |
|---|---|
| Base, PAM, consent, Plymouth, VIT branding | `vitos-base` |
| Security tools + Firejail profiles | `vitos-tools` |
| Telemetry + AI + CLI | `vitos-monitor` |
| Admin web dashboard | `vitos-dashboard` |
| Ghost Mode (WireGuard + Tor) | `vitos-ghost` |
| FreeIPA SSO | `vitos-sso` |
| CVE hardening + audit cron | `vitos-hardening` |
| VIT Bhopal site overlay (lab scopes, hostname, retention) | `vitos-vit-bhopal` |
| Custom kernel | `linux-image-vitos` (Linux 6.6.52 hardened) |
| ISO assembly | `live-build` (Kali rolling mode) |
