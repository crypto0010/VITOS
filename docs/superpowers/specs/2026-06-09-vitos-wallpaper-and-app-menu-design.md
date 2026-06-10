# VITOS wallpaper + curated application menu — design

Date: 2026-06-09
Status: approved (design); pending implementation plan

## Problem

Two user-facing branding/usability gaps on the installed/live XFCE desktop:

1. **Kali wallpaper still shows.** `branding/build-branding.sh` generates a LightDM
   greeter image, a Plymouth splash, and Calamares logo/icon — but **no XFCE desktop
   wallpaper and no backdrop config**, and `vitos-base` ships no XFCE/skel config. So
   `task-xfce-desktop` (Kali base) leaves Kali's default wallpaper on the desktop.
2. **No list of the security/AI applications.** There are **no XDG menu/category
   files and no per-tool `.desktop` launchers**. GUI tools may appear under generic
   freedesktop categories, but the CLI tools (nmap, sqlmap, hydra, hashcat, john,
   radare2, …) never appear in any menu, and there is no curated VITOS list.
   "Home" = the XFCE desktop (the `vitos-dashboard` web app has no apps page).

User decisions (captured via AskUserQuestion, 2026-06-09):

- App presentation: **dedicated "VITOS · Security" and "VITOS · AI" submenus** in the
  XFCE/Whisker Applications menu (native dropdown).
- CLI tools: **create launchers for CLI tools too** — clicking opens the tool in a
  terminal. Everything appears in the list.
- Wallpaper source: **generate from the existing VIT Bhopal logo** (dark gradient,
  matching the greeter style); apply everywhere; override Kali.
- AI section: **Ollama/Gemma chat + VITOS Dashboard**.
- volatility3: **install at firstboot** so "install all applications" is literally true.

## Key facts discovered (ground truth)

- DE is **XFCE** (`task-xfce-desktop`); greeter is **LightDM + lightdm-gtk-greeter**.
  Greeter background is already VITOS (set in `vitos-base/debian/postinst` →
  `/etc/lightdm/lightdm-gtk-greeter.conf.d/90-vitos.conf`). Lock screen (light-locker)
  reuses the greeter background, so **login + lock are already VITOS**.
- `vitos-tools` **wraps every tool**: `postinst` symlinks `/usr/local/bin/<tool>` →
  `/usr/sbin/vitos-run` (Firejail sandbox + telemetry to the VITOS bus). Canonical tool
  names (the symlink basenames vitos-run dispatches on):
  `nmap ncat wireshark tcpdump aircrack-ng ettercap bettercap scapy msfconsole sqlmap
  hydra john hashcat burpsuite binwalk exiftool fls volatility3 yara r2 ghidra strace
  ltrace autopsy`. **Launchers MUST call `/usr/local/bin/<tool>`** so telemetry/sandbox
  apply; calling the raw binary bypasses VITOS.
- `vitos-tools` **Depends on** all those tool packages (so they install), **except
  volatility3** which is deferred (not in Kali main; the package-list notes a pip
  follow-up).
- `branding/build-branding.sh` **is invoked during the build** (`live-build/build-iso.sh:7`),
  so extending it to emit the wallpaper PNG is consistent with the existing pattern.
- `vitos-base/debian/install` installs `usr/share/vitos/branding/` wholesale, so a
  generated `wallpaper.png` placed there ships to `/usr/share/vitos/branding/wallpaper.png`.
- Ollama model is registered as **`vitos-intent`** (Gemma 3 4B) via
  `ollama create vitos-intent -f /etc/vitos/Modelfile`; Ollama serves on
  `127.0.0.1:11434`. Interactive chat = `ollama run vitos-intent`.
- Dashboard = FastAPI/uvicorn on **`127.0.0.1:8443`** (no TLS configured → `http://`).

## Design

### Component 1 — Wallpaper everywhere (no Kali)

- **Asset (generated):** extend `branding/build-branding.sh` to emit a 1920×1080
  `wallpaper.png` (dark gradient `#0a0e2a`→`#1a1f4a`, centered VIT logo, caption
  "VITOS — Developed by Dr. Hemraj, VIT Bhopal") into
  `packages/vitos-base/usr/share/vitos/branding/wallpaper.png`.
- **Default backdrop (override Kali):** ship
  `includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml`
  with every `last-image`/`image-path` pointing at
  `/usr/share/vitos/branding/wallpaper.png` and `image-style=5` (zoomed). Shipping via
  **includes.chroot** (copied after packages) cleanly overrides whatever kali-themes
  ships at the same path — no dpkg file-conflict. Calamares copies `/etc/skel` into the
  installed user's home, and the live user also derives from `/etc/skel`.
- **Belt-and-suspenders:** `includes.chroot/etc/xdg/autostart/vitos-wallpaper.desktop`
  runs a tiny script on every XFCE login that `xfconf-query`s the backdrop to the VITOS
  PNG for all connected monitors (idempotent) — guarantees override even against a stale
  per-user xfconf.
- Out of scope: GRUB / live boot-menu artwork (not "wallpaper").

### Component 2 — "VITOS · Security" and "VITOS · AI" menu categories

All committed under **`vitos-tools`** (text files; no generation needed):

- **Per-tool launchers** `usr/share/applications/vitos-<tool>.desktop`:
  - GUI (`Terminal=false`, `Exec=/usr/local/bin/<tool>`): **wireshark, burpsuite, ghidra**.
  - Terminal/REPL (open a terminal, run the tool): **msfconsole, r2, scapy, bettercap,
    ettercap, sqlmap, autopsy** (autopsy starts its web server and prints a URL).
  - Terminal/CLI help+shell: **nmap, ncat, tcpdump, aircrack-ng, hydra, john, hashcat,
    binwalk, exiftool, fls, yara, strace, ltrace, volatility3**.
  - All `Categories=X-VITOS-Security;`.
- **Launcher helper** `usr/bin/vitos-launch-tool <tool> [--repl]` keeps the `.desktop`
  files trivial and centralizes terminal behavior:
  - `--repl`: `exec /usr/local/bin/<tool>` inside the terminal.
  - default: print a VITOS banner + `<tool> --help`/`-h` (best-effort), then
    `exec bash -i` (the wrapped tool is on PATH via `/usr/local/bin`).
  - terminal = `xfce4-terminal --title "VITOS · <Tool>" -e "vitos-launch-tool <tool> [...]"`
    (xterm fallback if xfce4-terminal absent).
- **AI launchers** (`Categories=X-VITOS-AI;`), also in `vitos-tools`:
  - `vitos-ai-chat.desktop` → `xfce4-terminal --title "VITOS AI (Gemma 3)" -e
    "vitos-launch-tool ollama --repl"` running `ollama run vitos-intent`
    (helper special-cases `ollama` → `ollama run vitos-intent`).
  - `vitos-dashboard.desktop` → `xdg-open http://127.0.0.1:8443`.
- **Categories:** `usr/share/desktop-directories/vitos-security.directory` and
  `vitos-ai.directory` (Name = "VITOS · Security" / "VITOS · AI", VITOS icon).
- **Menu merge:** `etc/xdg/menus/applications-merged/vitos.menu` defines the two
  submenus under `<Name>Xfce</Name>` by `<Category>X-VITOS-Security</Category>` /
  `X-VITOS-AI`. XFCE's `xfce-applications.menu` already `<MergeDir>`s
  `applications-merged`, so no edit of the base menu is required.
- `vitos-tools/debian/install` gains entries for all the above paths.

### Component 3 — Install all applications

- volatility3: add to the firstboot path a `pipx install volatility3` (fallback
  `pip install --break-system-packages volatility3`). The pip package's entrypoint is
  **`vol`**, but `vitos-run` dispatches on the name `volatility3` and resolves
  `/usr/bin/volatility3` (etc.) — so firstboot must also drop a small
  **`/usr/bin/volatility3` shim** that `exec`s `vol "$@"`, so `/usr/local/bin/volatility3`
  → vitos-run → the shim works. Its launcher is then included like any other CLI tool.
- Every other tool is already a hard dependency of `vitos-tools`.

### Component 4 — Verification (no ISO build)

- `tests/verify-appmenu.sh` (run in `kalilinux/kali-rolling`):
  - `desktop-file-validate` every `vitos-*.desktop` → no errors.
  - **Security launchers (`Categories` contains `X-VITOS-Security`):** parse the canonical
    tool list from `vitos-tools/debian/postinst` and assert **every tool has exactly one
    Security launcher** (drift/completeness guard) and every Security launcher maps to a
    known tool. Also assert each Security launcher's `Exec` routes through
    `/usr/local/bin/<tool>` or `vitos-launch-tool` (never a raw `/usr/bin` path) — sandbox
    not bypassed.
  - **AI launchers are exempt** from the two assertions above (they are exactly two:
    `vitos-ai-chat.desktop`, which runs the real `ollama run vitos-intent`, and
    `vitos-dashboard.desktop`, which uses `xdg-open`). The test asserts these two exist
    and are valid, nothing more about wrapping.
  - Validate `vitos.menu` is well-formed XML and references both `.directory` files.
  - Assert `xfce4-desktop.xml` references `/usr/share/vitos/branding/wallpaper.png`.
  - `vitos-launch-tool` smoke test in `VITOS_DRYRUN` mode (no real tools needed).
- `.github/workflows/verify-appmenu.yml` mirrors `verify-bootloader.yml` (push paths +
  workflow_dispatch). Build the ISO only when explicitly prompted.

## Files touched (summary)

- `branding/build-branding.sh` — emit `wallpaper.png`.
- `packages/vitos-base/usr/share/vitos/branding/wallpaper.png` — generated artifact.
- `live-build/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml`
- `live-build/config/includes.chroot/etc/xdg/autostart/vitos-wallpaper.desktop` (+ helper script)
- `packages/vitos-tools/usr/bin/vitos-launch-tool`
- `packages/vitos-tools/usr/share/applications/vitos-*.desktop` (24 + 2 AI)
- `packages/vitos-tools/usr/share/desktop-directories/vitos-{security,ai}.directory`
- `packages/vitos-tools/etc/xdg/menus/applications-merged/vitos.menu`
- `packages/vitos-tools/debian/install` — install the new paths.
- firstboot hook — `volatility3` install.
- `tests/verify-appmenu.sh`, `.github/workflows/verify-appmenu.yml`.

## Constraints

- Do **not** build the ISO unless explicitly prompted; prove via verify-appmenu CI.
- Direct push to `main` is blocked → feature branch + PR + squash merge.
- Launchers always go through the sandboxed `/usr/local/bin/<tool>` path.
- No dpkg file-conflicts: desktop/skel overrides ship via `includes.chroot`.

## Non-goals

- Redesigning the dashboard or adding an apps page to it.
- GRUB/boot-menu theming.
- Replacing the XFCE panel layout (only adding menu categories).
