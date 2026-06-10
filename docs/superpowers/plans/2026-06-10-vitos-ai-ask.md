# VITOS AI Ask Bar (PR C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a hotkey-triggered "ask anything" bar that routes the user's question to the local Gemma 3 model (Ollama) and shows the answer — fully offline.

**Architecture:** `vitos-ask` (POSIX sh) prompts via `rofi` (falling back to `yad`/`zenity`/stdin), runs `ollama run vitos-intent "<question>"`, and shows the answer in a scrollable dialog. It is launched from a **VITOS · AI** menu entry and from **Super+A**, registered non-destructively at login by a small `vitos-ask-keybind` autostart (it *adds* the binding via `xfconf-query` rather than shipping a full keyboard-shortcuts file that would clobber the XFCE defaults). `rofi`/`yad` are added to the package list; everything degrades gracefully if a tool is absent. A new section of `verify-branding.sh` validates it in the Kali CI container; no ISO build.

**Tech Stack:** POSIX sh, Ollama CLI (`vitos-intent` / Gemma 3), `rofi`/`yad`/`zenity`, XFCE `xfconf`, freedesktop `.desktop`, Debian packaging, GitHub Actions (Kali container).

**Branch:** `feat/vitos-ai-ask` (create off `feat/vitos-look-and-feel`). PR C base = `feat/vitos-look-and-feel` (stacked on PR #10).

**Reference spec:** `docs/superpowers/specs/2026-06-10-vitos-branding-identity-ai-design.md` (Component C).

**TDD adaptation:** Same as PRs A/B — strongest locally runnable check per task (`sh -n`, `VITOS_ASK_TEST=1`, `grep`, XML parse); authoritative gate is `verify-branding.sh` (Task 6) green in the Kali CI container (Task 7); the interactive ask flow is confirmed on hardware (needs a running Ollama + a display).

**Graceful degradation:** `vitos-ask` picks the best available prompt/answer tool and never hard-requires `rofi`/`yad`; the keybind autostart no-ops if `xfconf-query` is absent and only *adds* one binding, leaving all XFCE defaults intact.

---

## File Structure

AI ask bar (package `vitos-tools`):
- Create `vitos-v1/packages/vitos-tools/usr/bin/vitos-ask`
- Create `vitos-v1/packages/vitos-tools/usr/share/applications/vitos-ask.desktop`
- Modify `vitos-v1/packages/vitos-tools/debian/install`

Hotkey (ship via `includes.chroot`, non-destructive):
- Create `vitos-v1/live-build/config/includes.chroot/usr/local/bin/vitos-ask-keybind`
- Create `vitos-v1/live-build/config/includes.chroot/etc/xdg/autostart/vitos-ask-keybind.desktop`

Packages:
- Modify `vitos-v1/live-build/config/package-lists/vitos.list.chroot`

Verification:
- Modify `vitos-v1/tests/verify-branding.sh` (append Component-C section)
- Modify `.github/workflows/verify-branding.yml` (add C paths)

---

### Task 1: `vitos-ask` helper

**Files:**
- Create: `vitos-v1/packages/vitos-tools/usr/bin/vitos-ask`

- [ ] **Step 1: Write the script**

Create the file with EXACTLY:

```sh
#!/bin/sh
# vitos-ask — ask the local VITOS AI (Gemma 3 via Ollama) anything.
# A quick "ask bar": prompt via rofi (fallback yad/zenity/stdin), answer shown
# in a scrollable dialog. Fully offline — talks to the local ollama service
# (model: vitos-intent). Bound to Super+A and listed under VITOS · AI.
#
# VITOS_ASK_TEST=1 prints the resolved model/command and exits 0 (CI hook).
set -u
MODEL="vitos-intent"

prompt_tool() {
  if command -v rofi >/dev/null 2>&1; then
    rofi -dmenu -p "Ask VITOS AI" </dev/null
  elif command -v yad >/dev/null 2>&1; then
    yad --entry --title="VITOS AI" --text="Ask anything:"
  elif command -v zenity >/dev/null 2>&1; then
    zenity --entry --title="VITOS AI" --text="Ask anything:"
  else
    printf 'Ask VITOS AI: ' >&2; read -r line && printf '%s' "$line"
  fi
}
show_answer() {
  if command -v yad >/dev/null 2>&1; then
    yad --text-info --title="VITOS AI" --width=720 --height=480 --wrap --button=Close:0
  elif command -v zenity >/dev/null 2>&1; then
    zenity --text-info --title="VITOS AI" --width=720 --height=480
  else
    cat
  fi
}

if [ "${VITOS_ASK_TEST:-0}" = "1" ]; then
  if   command -v rofi   >/dev/null 2>&1; then pt=rofi
  elif command -v yad    >/dev/null 2>&1; then pt=yad
  elif command -v zenity >/dev/null 2>&1; then pt=zenity
  else pt=stdin; fi
  echo "MODEL=$MODEL RUN=ollama run $MODEL PROMPT_TOOL=$pt"
  exit 0
fi

command -v ollama >/dev/null 2>&1 || { echo "ollama not installed" >&2; exit 1; }

Q=$(prompt_tool)
[ -n "$Q" ] || exit 0
ans=$(ollama run "$MODEL" "$Q" 2>/dev/null)
[ -n "$ans" ] || ans="VITOS AI is unavailable — is the ollama service running?  (systemctl status ollama)"
printf 'Q: %s\n\n%s\n' "$Q" "$ans" | show_answer
```

- [ ] **Step 2: chmod + syntax + test-hook resolution**

```bash
cd /c/Users/HP/Documents/VITOS
F=vitos-v1/packages/vitos-tools/usr/bin/vitos-ask
chmod +x "$F"
sh -n "$F" && echo "SYNTAX OK"
VITOS_ASK_TEST=1 sh "$F"
```
Expected: `SYNTAX OK`, then a line `MODEL=vitos-intent RUN=ollama run vitos-intent PROMPT_TOOL=…` (the tool name depends on what's installed on the dev host; the `RUN=ollama run vitos-intent` part is what matters).

- [ ] **Step 3: Commit**

```bash
cd /c/Users/HP/Documents/VITOS
git add vitos-v1/packages/vitos-tools/usr/bin/vitos-ask
git commit -m "feat(ai): vitos-ask — local Gemma 3 ask bar (offline)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `vitos-ask` launcher (VITOS · AI)

**Files:**
- Create: `vitos-v1/packages/vitos-tools/usr/share/applications/vitos-ask.desktop`

- [ ] **Step 1: Create the launcher**

```bash
cd /c/Users/HP/Documents/VITOS
APPS=vitos-v1/packages/vitos-tools/usr/share/applications
cat > "$APPS/vitos-ask.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Ask VITOS AI
Comment=Ask the local Gemma 3 model anything (offline) — also on Super+A
Exec=vitos-ask
Icon=system-search
Terminal=false
Categories=X-VITOS-AI;
Keywords=ai;ask;search;gemma;ollama;vitos;
EOF
```

- [ ] **Step 2: Verify**

```bash
cd /c/Users/HP/Documents/VITOS
F=vitos-v1/packages/vitos-tools/usr/share/applications/vitos-ask.desktop
grep -q 'Exec=vitos-ask$' "$F" && echo "exec OK"
grep -q 'Categories=X-VITOS-AI;' "$F" && echo "category OK"
```
Expected: `exec OK`, `category OK`.

- [ ] **Step 3: Commit**

```bash
cd /c/Users/HP/Documents/VITOS
git add vitos-v1/packages/vitos-tools/usr/share/applications/vitos-ask.desktop
git commit -m "feat(menu): Ask VITOS AI launcher under VITOS · AI

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Super+A hotkey (non-destructive, via autostart)

**Files:**
- Create: `vitos-v1/live-build/config/includes.chroot/usr/local/bin/vitos-ask-keybind`
- Create: `vitos-v1/live-build/config/includes.chroot/etc/xdg/autostart/vitos-ask-keybind.desktop`

- [ ] **Step 1: Create the keybind registrar**

Create `…/usr/local/bin/vitos-ask-keybind` with EXACTLY:

```sh
#!/bin/sh
# Register Super+A -> vitos-ask in the xfce4-keyboard-shortcuts channel without
# clobbering the XFCE defaults (adds a single custom command binding). Run from
# /etc/xdg/autostart on XFCE login. Idempotent.
command -v xfconf-query >/dev/null 2>&1 || exit 0
P='/commands/custom/<Super>a'
cur=$(xfconf-query -c xfce4-keyboard-shortcuts -p "$P" 2>/dev/null || true)
[ "$cur" = "vitos-ask" ] && exit 0
xfconf-query -c xfce4-keyboard-shortcuts -p "$P" -s 'vitos-ask' 2>/dev/null \
  || xfconf-query -c xfce4-keyboard-shortcuts -p "$P" -n -t string -s 'vitos-ask' 2>/dev/null \
  || true
exit 0
```

- [ ] **Step 2: Create the autostart entry**

```bash
cd /c/Users/HP/Documents/VITOS
AUTO=vitos-v1/live-build/config/includes.chroot/etc/xdg/autostart
mkdir -p "$AUTO"
cat > "$AUTO/vitos-ask-keybind.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=VITOS AI Hotkey
Comment=Bind Super+A to the VITOS AI ask bar
Exec=/usr/local/bin/vitos-ask-keybind
OnlyShowIn=XFCE;
NoDisplay=true
X-XFCE-Autostart-Override=true
EOF
```

- [ ] **Step 3: chmod + verify**

```bash
cd /c/Users/HP/Documents/VITOS
K=vitos-v1/live-build/config/includes.chroot/usr/local/bin/vitos-ask-keybind
chmod +x "$K"
sh -n "$K" && echo "KEYBIND SYNTAX OK"
grep -q 'vitos-ask' "$K" && echo "binds vitos-ask OK"
grep -q '<Super>a' "$K" && echo "uses Super+A OK"
grep -q 'Exec=/usr/local/bin/vitos-ask-keybind' \
  vitos-v1/live-build/config/includes.chroot/etc/xdg/autostart/vitos-ask-keybind.desktop && echo "autostart exec OK"
```
Expected: `KEYBIND SYNTAX OK`, `binds vitos-ask OK`, `uses Super+A OK`, `autostart exec OK`.

- [ ] **Step 4: Commit**

```bash
cd /c/Users/HP/Documents/VITOS
git add vitos-v1/live-build/config/includes.chroot/usr/local/bin/vitos-ask-keybind \
        vitos-v1/live-build/config/includes.chroot/etc/xdg/autostart/vitos-ask-keybind.desktop
git commit -m "feat(ai): bind Super+A to vitos-ask (non-destructive autostart)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Install rofi + yad

**Files:**
- Modify: `vitos-v1/live-build/config/package-lists/vitos.list.chroot`

- [ ] **Step 1: Append the prompt/dialog packages**

Append to the end of `vitos-v1/live-build/config/package-lists/vitos.list.chroot`:

```
# VITOS AI ask bar — prompt (rofi) + answer dialog (yad). vitos-ask falls back
# to zenity/stdin if absent, so these never block the build.
rofi
yad
```

- [ ] **Step 2: Verify**

```bash
cd /c/Users/HP/Documents/VITOS
L=vitos-v1/live-build/config/package-lists/vitos.list.chroot
for p in rofi yad; do grep -qx "$p" "$L" && echo "listed: $p" || echo "MISSING: $p"; done
```
Expected: `listed: rofi`, `listed: yad`.

- [ ] **Step 3: Commit**

```bash
cd /c/Users/HP/Documents/VITOS
git add vitos-v1/live-build/config/package-lists/vitos.list.chroot
git commit -m "build: add rofi + yad for the VITOS AI ask bar

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Wire `vitos-ask` payload into the package

**Files:**
- Modify: `vitos-v1/packages/vitos-tools/debian/install`

- [ ] **Step 1: Append the install lines**

Append to `vitos-v1/packages/vitos-tools/debian/install`:

```
usr/bin/vitos-ask                                      usr/bin
usr/share/applications/vitos-ask.desktop               usr/share/applications
```

- [ ] **Step 2: Sanity-check every install source exists**

```bash
cd /c/Users/HP/Documents/VITOS/vitos-v1/packages/vitos-tools
missing=0
while read -r src dest; do
    [ -n "$src" ] || continue
    case "$src" in \#*) continue;; esac
    if [ ! -e "$src" ]; then echo "MISSING: $src"; missing=$((missing+1)); fi
done < debian/install
echo "missing=$missing"
cd /c/Users/HP/Documents/VITOS
```
Expected: `missing=0`

- [ ] **Step 3: Commit**

```bash
cd /c/Users/HP/Documents/VITOS
git add vitos-v1/packages/vitos-tools/debian/install
git commit -m "build(tools): install vitos-ask + launcher

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Extend `verify-branding.sh` with the AI-ask section

**Files:**
- Modify: `vitos-v1/tests/verify-branding.sh` (insert before `say "SUMMARY"`)
- Modify: `.github/workflows/verify-branding.yml` (add C paths)

- [ ] **Step 1: Insert the Component-C checks**

In `vitos-v1/tests/verify-branding.sh`, find this line (the SUMMARY header):

```sh
# ---------------------------------------------------------------------------
say "SUMMARY"
```

and insert the following block IMMEDIATELY BEFORE it:

```sh
# ---------------------------------------------------------------------------
# Component C — AI ask bar ----------------------------------------------------
ASK="$TOOLS/usr/bin/vitos-ask"
ASK_DESK="$APPS/vitos-ask.desktop"
KEYBIND="$INC/usr/local/bin/vitos-ask-keybind"
ASK_AUTO="$INC/etc/xdg/autostart/vitos-ask-keybind.desktop"

say "T12: vitos-ask resolves the local Gemma 3 model + launcher/hotkey wired"
sh -n "$ASK" && pass "T12 vitos-ask syntax OK" || fail "T12 vitos-ask syntax error"
OUT=$(VITOS_ASK_TEST=1 sh "$ASK")
echo "$OUT" | grep -q 'RUN=ollama run vitos-intent' && pass "T12 vitos-ask -> ollama vitos-intent" || fail "T12 vitos-ask resolve wrong: $OUT"
if desktop-file-validate "$ASK_DESK" >/tmp/dfv.out 2>&1; then pass "T12 vitos-ask.desktop valid"; else fail "T12 vitos-ask.desktop INVALID"; cat /tmp/dfv.out; fi
grep -q 'Categories=.*X-VITOS-AI' "$ASK_DESK" && pass "T12 vitos-ask.desktop in VITOS · AI" || fail "T12 vitos-ask.desktop lacks X-VITOS-AI"
grep -q 'Exec=vitos-ask' "$ASK_DESK" && pass "T12 vitos-ask.desktop runs vitos-ask" || fail "T12 vitos-ask.desktop Exec wrong"
sh -n "$KEYBIND" && pass "T12 vitos-ask-keybind syntax OK" || fail "T12 vitos-ask-keybind syntax error"
grep -q 'vitos-ask' "$KEYBIND" && grep -q '<Super>a' "$KEYBIND" && pass "T12 keybind maps Super+A -> vitos-ask" || fail "T12 keybind mapping wrong"
if desktop-file-validate "$ASK_AUTO" >/tmp/dfv.out 2>&1; then pass "T12 keybind autostart valid"; else fail "T12 keybind autostart INVALID"; cat /tmp/dfv.out; fi
grep -q 'Exec=/usr/local/bin/vitos-ask-keybind' "$ASK_AUTO" && pass "T12 autostart runs the registrar" || fail "T12 autostart Exec wrong"
for p in rofi yad; do
    grep -qx "$p" "$REPO_ROOT/vitos-v1/live-build/config/package-lists/vitos.list.chroot" \
      && pass "T12 package listed: $p" || fail "T12 package missing: $p"
done

# ---------------------------------------------------------------------------
say "SUMMARY"
```

- [ ] **Step 2: Add the new required-file preflight entries**

In `verify-branding.sh`, find the preflight loop (it already lists build-branding.sh, vitos.script, vitos-theme, xsettings.xml from PR B) and add the two AI-ask files. Replace:

```sh
         "$TOOLS/usr/bin/vitos-theme" \
         "$INC/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"; do
```

with:

```sh
         "$TOOLS/usr/bin/vitos-theme" \
         "$INC/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" \
         "$TOOLS/usr/bin/vitos-ask" \
         "$INC/usr/local/bin/vitos-ask-keybind"; do
```

- [ ] **Step 3: Add C paths to the workflow triggers**

In `.github/workflows/verify-branding.yml`, find:

```yaml
      - "vitos-v1/live-build/config/package-lists/vitos.list.chroot"
      - "vitos-v1/tests/verify-branding.sh"
      - ".github/workflows/verify-branding.yml"
```

and replace with:

```yaml
      - "vitos-v1/live-build/config/package-lists/vitos.list.chroot"
      - "vitos-v1/packages/vitos-tools/usr/bin/vitos-ask"
      - "vitos-v1/packages/vitos-tools/usr/share/applications/vitos-ask.desktop"
      - "vitos-v1/live-build/config/includes.chroot/usr/local/bin/vitos-ask-keybind"
      - "vitos-v1/live-build/config/includes.chroot/etc/xdg/autostart/vitos-ask-keybind.desktop"
      - "vitos-v1/tests/verify-branding.sh"
      - ".github/workflows/verify-branding.yml"
```

- [ ] **Step 4: Syntax-check + run host-runnable parts**

```bash
cd /c/Users/HP/Documents/VITOS
sh -n vitos-v1/tests/verify-branding.sh && echo "TEST SYNTAX OK"
VITOS_ASK_TEST=1 sh vitos-v1/packages/vitos-tools/usr/bin/vitos-ask
python -c "import yaml; yaml.safe_load(open('.github/workflows/verify-branding.yml')); print('YAML OK')" 2>/dev/null \
  || py -c "import yaml; yaml.safe_load(open('.github/workflows/verify-branding.yml')); print('YAML OK')" 2>/dev/null \
  || echo "(pyyaml unavailable)"
```
Expected: `TEST SYNTAX OK`, the `RUN=ollama run vitos-intent` line, `YAML OK`.

- [ ] **Step 5: Commit**

```bash
cd /c/Users/HP/Documents/VITOS
git add vitos-v1/tests/verify-branding.sh .github/workflows/verify-branding.yml
git commit -m "test(branding): add AI ask-bar checks (vitos-ask, hotkey)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Push, open PR C, confirm CI green (no ISO build)

- [ ] **Step 1: Push the branch**

```bash
cd /c/Users/HP/Documents/VITOS
git push -u origin feat/vitos-ai-ask
```

- [ ] **Step 2: Open the PR (base = PR B branch — stacked)**

```bash
cd /c/Users/HP/Documents/VITOS
gh pr create --base feat/vitos-look-and-feel --head feat/vitos-ai-ask \
  --title "feat: VITOS AI ask bar (Super+A) — ask the local Gemma 3 anything" \
  --body "Component C of docs/superpowers/specs/2026-06-10-vitos-branding-identity-ai-design.md. Adds vitos-ask: a rofi-based 'ask anything' bar that runs the question through the local ollama model (vitos-intent / Gemma 3) and shows the answer — fully offline. Launchable from VITOS · AI and from Super+A (bound non-destructively at login). Verified by verify-branding CI; no ISO build. Stacked on #10.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 3: Confirm verify-branding is green**

```bash
cd /c/Users/HP/Documents/VITOS
sleep 12
gh run list --workflow=verify-branding.yml --branch=feat/vitos-ai-ask --limit 1 \
  --json databaseId,status,conclusion,headSha
gh run view <id> --log | grep -E "PASS T12|FAIL|ALL CASES PASSED|CASE\(S\) FAILED" | tail -40
```
Expected: every `PASS`, final `ALL CASES PASSED — identity + credits verified.`, run `conclusion: success`.

- [ ] **Step 4: Report to the user.** Do NOT merge or build the ISO. All three components (A/B/C) are now CI-green stacked PRs (#9 → #10 → C). Visual/interactive confirmation (themes, boot/lock animation, the ask bar) is on hardware after the next user-prompted build.

---

## Self-Review

**1. Spec coverage (Component C):**
- #7 Ollama "ask anything" bar → Task 1 (`vitos-ask` → `ollama run vitos-intent`); enforced by T12. ✅
- Prompt via rofi (fallback yad/zenity) + answer dialog → Task 1. ✅
- Super+A hotkey → Task 3 (non-destructive autostart); enforced by T12. ✅
- VITOS · AI menu entry → Task 2 (reuses the existing `X-VITOS-AI` category from PR #8). ✅
- Packages (rofi/yad) → Task 4; enforced by T12. ✅
- Package wiring → Task 5. ✅
- CI, no ISO build → Tasks 6, 7. ✅

**2. Placeholder scan:** No TBD/TODO; all file contents complete; `<id>` in Task 7 is a runtime value substituted from the JSON output, not a plan placeholder. ✅

**3. Type/name consistency:**
- `vitos-ask` name identical in Task 1 (file), Task 2 (`Exec=`), Task 3 (keybind value), Task 5 (install), test T12. ✅
- `VITOS_ASK_TEST` hook + `RUN=ollama run vitos-intent` output identical between Task 1 and test T12. ✅
- Category `X-VITOS-AI` matches the existing AI category (PR #8) used by `vitos-ai-chat`/`vitos-dashboard`, so `vitos-ask` lands in the same submenu. ✅
- Hotkey `<Super>a` + binding value `vitos-ask` identical in Task 3 and test T12. ✅
- Model `vitos-intent` matches the Ollama model created by vitos-monitor's postinst (`ollama create vitos-intent`). ✅

No issues found.
