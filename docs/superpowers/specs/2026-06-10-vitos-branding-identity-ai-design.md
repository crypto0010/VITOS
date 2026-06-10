# VITOS Branding, Identity & AI Ask — Design

**Date:** 2026-06-10
**Status:** Approved (brainstorming) — pending spec review
**Branch base:** `feat/vitos-wallpaper-app-menu` (this work stacks on PR #8; the
credits/About + ask-bar reuse PR #8's app menu, and the punchline edits PR #8's
wallpaper). Once #8 merges, rebase onto `main`.

## Goal

Deepen VITOS's identity so the OS reads as a VIT Bhopal product end to end:
remove every user-facing "Kali" version string, surface the team and a Special
Thanks, stamp the punchline across the OS, ship a switchable themed look with an
animated boot and a branded sleep/lock screen, and add a local-AI "ask anything"
bar. Verification is structural in a Kali CI container now; final visual
confirmation is on real hardware after a (separately, user-prompted) ISO build.

## Canonical strings (verbatim — do not alter)

- **Punchline:** `Designed at VIT Bhopal for VITians`
- **Identity line:** `Designed and developed at VIT Bhopal — Cybersecurity and Digital Forensics Lab`
- **Special Thanks:** `Hon'ble Ms. Kadhambari S. Viswanathan`
- **Version:** `1.0.2` (matches the website footer/download section)

## Team (single source of truth: `website/index.html`)

Leadership (3): Dr. Hemraj Shobharam Lamkuche (Project Director), Dr. Pon
Harshavardhanan (Chief Mentor), Dr. Saravanan D. (Division Head).
Contributing team (17): Matrupriya Dibyanshu Panda, Spandan Gope, Bharat
Raghuvanshi, Mayank Singh Bhadouria, Advait Sahu, Aayushman Arora, Harsh Singh,
Satyanarayana Murthy V, Ravi Shankar, Agnibha, Leonardo, Mannat Pal, Ambika,
Rashmi, Nahal, Piyush, Krishno.

The credits surfaces (HTML + terminal) are validated against this list by CI so
they can never silently drift from the website.

## Requirements covered

1. Credits listing all website contributors (#1) — Component A.
2. Customized sleep UI, modern cybersecurity look (#2) — Component B.
3. Punchline "Designed at VIT Bhopal for VITians" (#3) — all components (A.3).
4. Special Thanks to Hon'ble Ms. Kadhambari S. Viswanathan (#4) — Component A.
5. More animations and themes (#5) — Component B.
6. Version shows VITOS / VIT Bhopal lab, never "Kali" (#6) — Component A.
7. Ollama-based "ask anything" search bar (#7) — Component C.

## Tech stack

POSIX sh, freedesktop `.desktop`/`.directory`, XFCE `xfconf`, GTK/icon themes
(from Kali repos, composed — not authored), Plymouth `script` module,
`xfce4-screensaver`, `rofi` (+ `yad`/`zenity` fallback), Ollama HTTP/CLI
(`vitos-intent` / Gemma 3), ImageMagick (`convert`), Debian packaging,
GitHub Actions (Kali container).

---

## Component A — Identity & Credits (#6, #1, #4, #3)

### A1. Version/identity rebrand (#6)

Ship VITOS identity files via `includes.chroot` (copied after packages, so they
override the Kali base with no dpkg conflict):

- `/usr/lib/os-release` and `/etc/os-release` (ship both; some tooling reads each):
  - `NAME="VITOS"`, `ID=vitos`, `ID_LIKE=debian` (kept for tool compatibility),
    `PRETTY_NAME="VITOS — VIT Bhopal"`, `VERSION="1.0.2"`, `VERSION_ID="1.0.2"`,
    `VERSION_CODENAME=vitos`, `HOME_URL`/`SUPPORT_URL` → the VITOS site,
    and a custom `VITOS_ORIGIN="Designed and developed at VIT Bhopal — Cybersecurity and Digital Forensics Lab"`.
- `/etc/lsb-release`: `DISTRIB_ID=VITOS`, `DISTRIB_RELEASE=1.0.2`,
  `DISTRIB_CODENAME=vitos`,
  `DISTRIB_DESCRIPTION="VITOS — Designed and developed at VIT Bhopal, Cybersecurity and Digital Forensics Lab"`.
- `/etc/issue`, `/etc/issue.net`, `/etc/motd`: VITOS banner + identity line +
  punchline. No "Kali".
- Dashboard `vitos-v1/packages/vitos-dashboard/web/src/pages/About.tsx`: replace
  any "Kali"/version text with VITOS + the identity line + version 1.0.2.
- Optional: a neofetch/fastfetch config under `/etc/skel` (or `/etc/`) with a
  VITOS ASCII logo so `neofetch` shows VITOS, if the tool is present.

**Scoped OUT, with rationale (documented so nobody is surprised):**
- `uname -r` kernel string still contains the base identifier — renaming it
  requires a full custom-kernel rebuild; out of scope for a branding pass.
- `/etc/apt/sources.list` still points at the Kali rolling mirror — changing it
  would break package updates. Neither is a user "version check" surface.

### A2. Credits — both GUI and terminal (#1, #4)

- **GUI:** `vitos-about.html` — self-contained, **offline** (no CDN; system-font
  stack with monospace/sans fallback), neon-on-dark to match the website.
  Sections: title + punchline, leadership (3), all 17 contributors, **Special
  Thanks — Hon'ble Ms. Kadhambari S. Viswanathan, for her support**, the lab
  credit/identity line, and `VITOS v1.0.2`. Launcher `vitos-about.desktop`
  (`Exec=xdg-open <path>/vitos-about.html`, `Terminal=false`).
- **Terminal:** `vitos-credits` — ASCII VITOS banner (reuse `banner-ascii.txt`
  style) + ANSI-colored sections with the same content. Launcher
  `vitos-credits.desktop` (`Terminal=true`).
- Both launchers live in a new **VITOS · About** menu category
  (`X-VITOS-About`) with its own `.directory`, merged into the existing
  `vitos.menu`. Shipped in the `vitos-tools` package alongside the existing
  launchers.
- **Drift guard:** CI parses the leadership + contributor names from
  `website/index.html` and asserts each appears in **both** `vitos-about.html`
  and `vitos-credits`, plus the Special Thanks name in both.

### A3. Punchline placement (#3)

`Designed at VIT Bhopal for VITians` appears on: the desktop wallpaper, the
lock background, the LightDM greeter background, the Plymouth boot splash,
`/etc/issue` + MOTD, and the About + credits screens. Implemented by extending
`build-branding.sh` annotations (B references the same generator) and the
identity files above.

---

## Component B — Look & Feel: themes, animations, sleep UI (#5, #2)

### B1. Switchable themes (#5)

Three **VITOS presets**, each = a (GTK theme + icon theme + xfwm4 theme + accent
+ wallpaper variant) tuple, composed from established dark themes available in
the Kali repos (no theme engine authored from scratch):
- **VITOS Neon** — cyan accent (default).
- **VITOS Matrix** — green accent.
- **VITOS Stealth** — near-black, muted accent.

A `vitos-theme <preset>` switcher applies the preset via `xfconf-query`
(xsettings `Net/ThemeName`, `Net/IconThemeName`, xfwm4 `theme`) and sets the
matching wallpaper. Three `.desktop` launchers under a **VITOS · Themes**
category (`X-VITOS-Theme`). Default preset applied at build via `/etc/skel`
xsettings/xfwm4 XML. `build-branding.sh` generates the three wallpaper variants
(`wallpaper-neon.png`, `wallpaper-matrix.png`, `wallpaper-stealth.png`), each
carrying the punchline; the default `wallpaper.png` (from PR #8) becomes the Neon
variant. Required theme/icon packages added to `vitos.list.chroot`.

### B2. Animations (#5)

- **Boot:** enhance the existing `vitos.script` Plymouth theme — pulsing/fading
  VIT logo + a progress bar + a subtle scanline, driven by the Plymouth `script`
  module's refresh callback. Keep it lightweight and resolution-tolerant.
- **Desktop:** enable the xfwm4 compositor with subtle fade/shadow (and box-move
  off) via `/etc/skel` xfwm4 XML. Low-risk eye-candy only.

### B3. Sleep/lock UI (#2)

- Install `xfce4-screensaver` (added to `vitos.list.chroot`).
- Generate `lock-background.png` (VIT logo + punchline, cyber styling) in
  `build-branding.sh`.
- Configure via `/etc/skel` xfconf (`xfce4-screensaver.xml`): lock on suspend
  and after an idle timeout, with the branded background and an on-brand idle
  saver (matrix/particle-style where the screensaver supports it).
- **Guaranteed deliverable:** the branded lock screen + punchline. The exact
  idle animation depends on what `xfce4-screensaver` offers on the target and is
  confirmed on hardware.

---

## Component C — Ollama "ask anything" bar (#7)

`vitos-ask` — a small POSIX helper that:
1. Prompts for a question via `rofi -dmenu` (cyber-styled theme), falling back to
   `yad --entry` then `zenity --entry` if `rofi` is absent.
2. Sends the question to the local model — `ollama run vitos-intent` (or the
   `127.0.0.1:11434` HTTP API via `curl`), fully offline.
3. Displays the answer in a scrollable dialog (`yad`/`zenity --text-info`, or a
   terminal pager fallback).

Bound to a global hotkey (**Super+A**) via `/etc/skel` xfce keyboard-shortcuts
XML, plus a **VITOS · AI** menu launcher (`vitos-ask.desktop`). Consistent with
the existing `vitos-ai-chat` launcher (AI tools use the real Ollama binary, not
the `/usr/local/bin` sandbox — same exemption as PR #8). A `VITOS_ASK_TEST=1`
hook prints the resolved prompt/command and exits 0 for CI, mirroring
`vitos-launch-tool`.

---

## Components / units (isolation & interfaces)

| Unit | Responsibility | Interface | Depends on |
|------|----------------|-----------|------------|
| identity files (`includes.chroot`) | static VITOS os-release/lsb/issue/motd | files on disk | — |
| `About.tsx` edit | dashboard version text | React component | dashboard build |
| `vitos-about.html` + launcher | GUI credits | `xdg-open` | app menu (PR #8) |
| `vitos-credits` + launcher | terminal credits | run in terminal | — |
| `build-branding.sh` (extend) | wallpaper variants, lock bg, punchline | PNGs in branding dir | ImageMagick |
| `vitos-theme` + 3 launchers | apply a named preset | `xfconf-query` | theme/icon pkgs |
| `vitos.script` (Plymouth) | animated boot | Plymouth script module | plymouth |
| `/etc/skel` XML (xsettings/xfwm4/screensaver/shortcuts) | defaults | xfconf XML | XFCE |
| `xfce4-screensaver` config + lock bg | branded sleep/lock | xfconf | xfce4-screensaver |
| `vitos-ask` + launcher + hotkey | AI ask bar | rofi/yad → Ollama | ollama, rofi |
| `verify-branding.sh` + `.yml` | structural gate | Kali CI | all above |

## Verification

New `vitos-v1/tests/verify-branding.sh` + `.github/workflows/verify-branding.yml`
(Kali container, ~2–4 min, no ISO):
- **Identity:** `os-release`/`lsb-release` parse cleanly; `ID=vitos`; identity
  line present; **no case-insensitive "kali"** in `os-release`, `lsb-release`,
  `issue`, `issue.net`, `motd`, or `About.tsx`.
- **Punchline:** exact string present in the branding generator outputs (asserted
  via the `convert` annotations in `build-branding.sh`), `issue`, MOTD, About,
  credits.
- **Credits drift:** every leadership + contributor name parsed from
  `website/index.html` appears in both `vitos-about.html` and `vitos-credits`;
  Special Thanks name in both.
- **Launchers:** `vitos-about`, `vitos-credits`, 3 theme launchers, `vitos-ask`
  pass `desktop-file-validate`; categories correct; menu XML well-formed and
  references the new `.directory` files.
- **Themes:** `vitos-theme` `sh -n`; each preset references a wallpaper variant
  that `build-branding.sh` generates; default xsettings references a shipped
  theme name.
- **Boot/lock:** `vitos.plymouth` references `vitos.script`; both present;
  `xfce4-screensaver.xml` + lock-background path consistent across generator and
  config.
- **Ask bar:** `vitos-ask` `sh -n`; `VITOS_ASK_TEST=1` resolves the Ollama
  target (`vitos-intent`).
- **`build-branding.sh`** passes `bash -n` and its assertions (emits the
  variants + lock bg + punchline).

## Execution plan (3 stacked PRs, one shared spec)

Each component becomes its own small, independently CI-green PR so reviews stay
tractable:
- **PR A — Identity & Credits** (base = `feat/vitos-wallpaper-app-menu`): A1–A3 +
  the About/credits half of `verify-branding`.
- **PR B — Look & Feel** (base = PR A): B1–B3 + theme/boot/lock checks.
- **PR C — AI Ask bar** (base = PR B): C + ask-bar checks.

Standing rules: feature branch + PR + squash merge only; **no direct push to
main**; **no ISO build** until explicitly requested; commit trailer
`Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`; PR body
trailer `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Do
not commit the user's untracked files (`VITOS Error.mp4`, `error*.jpeg`,
`grub_fix.pdf`).

## Out of scope

- Kernel `uname` string and apt sources (see A1 rationale).
- Authoring new GTK theme engines (we compose existing dark themes).
- Any ISO build or merge (visual confirmation deferred to hardware).
