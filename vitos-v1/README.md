# VITOS v1

Debian-based academic security distro for VIT cybersecurity labs with
AI-powered behavioral monitoring (Ollama + Isolation Forest), Firejail-
sandboxed pentesting tools, eBPF/auditd telemetry, and a `vitosctl` admin
CLI.

See `docs/superpowers/specs/2026-04-07-vitos-sp1-base-iso-design.md` for the
full design spec and `docs/superpowers/plans/2026-04-07-vitos-v1-implementation.md`
for the step-by-step implementation plan.

## Build

Requires a Linux build host (or Windows + Docker Desktop with WSL2) with
`/dev/kvm` available.

```bash
docker build -t vitos-builder vitos-v1/

# 1. Kernel (~30 min first time)
docker run --rm -v "$PWD:/build" vitos-builder \
  -c '/build/vitos-v1/kernel/build-kernel.sh'

# 2. Each Debian package
for pkg in vitos-base vitos-tools vitos-monitor; do
  docker run --rm -v "$PWD:/build" vitos-builder -c \
    "cd /build/vitos-v1/packages/$pkg && dpkg-buildpackage -us -uc -b && \
     mv ../${pkg}_*.deb /build/vitos-v1/live-build/config/packages.chroot/"
done

# 3. ISO (~60 min first time, includes 3 GB Ollama model download)
docker run --rm --privileged -v "$PWD:/build" vitos-builder \
  -c '/build/vitos-v1/live-build/build-iso.sh'

# 4. Smoke test
docker run --rm --privileged --device /dev/kvm -v "$PWD:/build" vitos-builder \
  -c '/build/vitos-v1/tests/smoke-test.sh'
```

Output: `vitos-v1/vitos-v1-YYYYMMDD-amd64.iso` (~4.7 GB).

## Default credentials (CHANGE IMMEDIATELY)

- `admin` / `changeme` — full sudo
- `student` / `changeme` — sandboxed, no sudo

Both accounts are forced to change password on first login. SP6 will replace
them with FreeIPA SSO and delete both default accounts on join.

## Layers

| Layer | Package | Owner |
|---|---|---|
| Base, PAM, consent, Plymouth, branding | `vitos-base` | Tasks 3, 16 |
| Security tools + Firejail | `vitos-tools` | Tasks 4–5 |
| Telemetry + AI + CLI | `vitos-monitor` | Tasks 6–13 |
| Custom kernel | `linux-image-vitos` | Task 2 |
| ISO assembly | `live-build` | Task 14 |
