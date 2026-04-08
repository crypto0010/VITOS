# VITOS Faculty Quickstart

A 1-page guide for VIT Bhopal cybersecurity faculty managing the lab.

> **VITOS** is designed and developed at the **Cybersecurity and Digital
> Forensics Lab, VIT Bhopal University**, led by **Dr. Hemraj Shobharam
> Lamkuche** (Project Director, Senior Assistant Professor 100541) and
> **Pon Harshavardhanan** (Chief Mentor). Full team credits in
> [`AUTHORS.md`](../../AUTHORS.md). Contact: **vitbhopal.os@gmail.com**.

## Sign in

1. Open `https://<your-lab-host>:8443/` in any browser on the lab VLAN.
2. Sign in with your VIT FreeIPA credentials. (You must be in the
   `vitos-admins` group; ask the lab admin if not.)
3. Accept the self-signed TLS certificate. The lab CA install procedure
   is in `docs/deployment/lab-workstation-image.md`.

## Daily console

The **Console** tab is the live view. Left rail = students online, with a
colour-coded risk score (green = Normal, yellow = Suspicious, orange =
Warning, red = Critical). Click any student to:

- See their live terminal (read-only by default).
- Click **Read/Write** to take over interactively. The student is shown a
  banner the moment you do.
- Click **Freeze** to pause their session (resumable).
- Click **Isolate** to drop their network namespace's veth (also
  resumable via **Release**).
- Click **Report** to download a PDF incident summary.

The **AI Insight** panel at the bottom streams the latest LLM rationale
for each alert. The risk score is composite — see the spec for the exact
weighting — but the hard rule is: **Critical requires anomaly > 0.7
AND malicious-intent label AND lab-scope breach**. The LLM alone can
never push a session past Warning.

## Activating a lab exercise

The 8 standard scopes ship under `/etc/vitos/lab-scopes/`. From the
**Scopes** tab in the dashboard, paste a manifest's contents into the
textarea and click **Activate**. The AI engine restarts automatically
and starts using the new scope to decide what's "in scope" for each
student session.

| Code | File | Purpose |
|---|---|---|
| Recon-101 | `recon-101.yaml` | Passive + active recon basics |
| Exploit-201 | `exploit-201.yaml` | CTF exploitation range |
| Forensics-301 | `forensics-301.yaml` | Disk + memory forensics, no network |
| Malware-401 | `malware-401.yaml` | Sandboxed analysis on VLAN 20 |
| Wireless-501 | `wireless-501.yaml` | Lab AP only |
| Web-601 | `web-601.yaml` | OWASP Top 10 on VLAN 30 |
| Mobile-701 | `mobile-701.yaml` | Android emulator only |
| Capstone-801 | `capstone-801.yaml` | Full lab range, end of semester |

## Ghost Mode (research only)

Ghost Mode routes a researcher's traffic through WireGuard + Tor inside
an isolated network namespace. **It is gated behind dual approval and
is not for student use.** Internal logging continues — Ghost Mode hides
the *external* trace, not the academic-integrity audit.

To enable for a researcher:

```
sudo vitosctl ghost enable <username> --profile default
# A second admin (must be in vitos-ghost-approvers, must NOT be you)
# then runs:
sudo vitosctl ghost approve <username>.default
```

## Incident response

1. Spot a Critical alert in the Console.
2. Read the AI rationale and look at the live terminal.
3. If genuine: **Isolate** the session, then **Report → PDF** for the
   case file.
4. Escalate to the academic-integrity committee with the PDF attached.
5. **All AI flags are advisory only.** No automated punishment ever.
6. To pause retention deletion on a specific student's logs (so you can
   investigate beyond the 180-day window), `touch /var/lib/vitos/retention.hold`
   on the workstation.

## Where to look when things break

| Symptom | Check |
|---|---|
| Dashboard won't load | `systemctl status vitos-dashboard caddy` |
| No alerts coming through | `systemctl status vitos-ai vitos-busd ollama` |
| Student session not appearing | `vitosctl session list` and `/run/vitos/sessions/` |
| AI engine returning Unknown for everything | `curl http://127.0.0.1:11434/api/tags` (Ollama health) |
| Need to revoke ghost mode | `sudo vitosctl ghost disable <id>` |

## Contact

Lab operations: `vitbhopal.os@gmail.com`
