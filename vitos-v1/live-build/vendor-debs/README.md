# Vendored .debs

Packages that VITOS needs but that have (temporarily or permanently) left the
kali-rolling / Debian-testing archives. `build-iso.sh` copies every `*.deb` here
into `config/packages.chroot/` (after verifying `SHA256SUMS`) so live-build picks
them up from its local repo.

## firejail_0.9.80-1_amd64.deb

Kali **removed firejail from kali-rolling on 2026-06-08** (and kali-dev on
2026-06-05); Debian removed it from *testing* on 2026-06-06 over RC bug #1134557.
It remains in Debian *unstable* at 0.9.80-1, which is the exact version Kali last
shipped. Source of this file:

    https://deb.debian.org/debian/pool/main/f/firejail/firejail_0.9.80-1_amd64.deb

`vitos-tools` now *Recommends* (not Depends) firejail, so if this vendored copy
or its deps ever become uninstallable the ISO build still succeeds — it just
ships without the Firejail sandbox until upstream restores the package. Deps
(`libapparmor1`, `libc6`, `libselinux1`) are all present in kali-rolling.

To refresh/replace, drop the new `.deb` here and regenerate `SHA256SUMS`:

    sha256sum *.deb > SHA256SUMS
