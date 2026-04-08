# VITOS Lab Workstation Deployment

How to image a fresh VIT Bhopal cybersecurity lab workstation with VITOS.

## What you need

- The latest VITOS release: **5 part files + `SHA256SUMS` + `REASSEMBLE.md`**
  from https://github.com/crypto0010/VITOS/releases
- A 16 GB+ USB key
- A workstation with: x86_64 CPU, ≥ 8 GB RAM, ≥ 64 GB disk, Ethernet on the lab VLAN
- The lab CA certificate (for the dashboard's TLS), in `lab-ca.pem`
- The FreeIPA admin password (you'll be prompted for it once per host)

## One-time prep

```bash
# Reassemble the ISO
cat vitos-v1-*-amd64.part*.iso > vitos-v1-amd64.iso
sha256sum -c SHA256SUMS

# Stage the unattended installer config on a second USB key
mkfs.vfat /dev/sdY1
mount /dev/sdY1 /mnt/usb
cp vitos-v1/live-build/config/includes.installer/preseed.cfg /mnt/usb/
cp /etc/vitos/sso.toml /mnt/usb/sso.toml         # see vitos-sso/etc/vitos/sso.toml.example
echo -n 'YOUR-IPA-ADMIN-PW' > /mnt/usb/sso.password
chmod 0600 /mnt/usb/sso.password
umount /mnt/usb

# Burn the live ISO to the install USB
sudo dd if=vitos-v1-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

## Per-workstation deployment

1. Boot the workstation from the **install USB** (sdX).
2. At the GRUB / isolinux menu, pick **Install (preseed)**.
3. Plug in the **config USB** (sdY) when the installer asks for media.
4. Walk away. The installer will:
   - Partition the disk with ext4 + LUKS
   - Install all 8 VITOS packages
   - Read `/sso.toml` + `/sso.password` from the config USB
   - Run `vitos-sso/join.sh` to join the FreeIPA realm
   - Render the hostname template (`vitos-bhopal-lab3-NN`)
   - Reboot
5. After reboot, sign in with any FreeIPA credential. The hardcoded
   `admin`/`student` accounts have been deleted; their pre-join home
   directories are archived under `/var/lib/vitos/legacy-homes/`.

## Verification checklist

After the workstation comes up, run on the dashboard host:

```bash
sudo vitosctl status
sudo vitosctl ghost list                  # should be empty
curl -k https://<hostname>:8443/api/health
sudo lynis audit system --quick --profile /etc/lynis/profiles/vitos.prf | grep 'Hardening index'
```

Expected:
- All VITOS services `active`
- No active or pending ghost-mode tokens
- `/api/health` returns `{"ok":true,…}`
- Lynis hardening index ≥ 70

## Rollback

If a workstation needs to be wiped and re-imaged: boot the install USB
again. The preseed will repartition the disk (LUKS passphrase from the
USB key), wiping everything. Student work that needs to survive a
re-image lives in the FreeIPA-authenticated user's home dir on the
shared NAS, not on local disk.

## Pilot bring-up checklist

Before opening the lab to students:

- [ ] At least 2 admins in `vitos-admins`
- [ ] At least 2 admins in `vitos-ghost-approvers`, with no overlap to ensure dual control
- [ ] FreeIPA realm reachable from every workstation
- [ ] Lab VLAN routes match each scope manifest's `allowed_targets`
- [ ] One faculty member has run a Recon-101 dry run end-to-end
- [ ] First 3 sessions per pilot student tagged `baseline=true` in `vitos-ai`
- [ ] Faculty consent banner visible at `/login`
- [ ] Pen-test report from `docs/security/vitos-pentest-report.md` signed off
