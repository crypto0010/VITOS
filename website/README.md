# VITOS website

Single-file marketing site for VITOS — Three.js WebGL hero, dark/light theme,
cyber-hacking aesthetic, fully self-contained (one HTML file + the VIT logo PNG).
No build step, no node_modules.

## Preview locally

```bash
# from the repo root
python3 -m http.server -d website 8000
# then open http://localhost:8000/
```

Or just double-click `index.html` (most browsers will open it directly; Three.js
loads from a CDN via an importmap so an internet connection is required on
first load).

## Deploy via GitHub Pages

1. In the repo settings → **Pages**:
   - Source: **Deploy from a branch**
   - Branch: **main** · folder: **`/website`** (or **`/docs`** if you move it)
2. Save. GitHub will publish at `https://crypto0010.github.io/VITOS/`
3. Custom domain: optionally set `vitos.vitbhopal.ac.in` (CNAME) and add
   `website/CNAME` containing that hostname.

## What's in the file

- **Hero:** Three.js WebGL scene — wireframe icosahedron + 800-particle
  spherical field + two orbit rings + mouse parallax. Re-tints on theme switch.
- **Sections:** About / Features (8 packages) / Audience (students &
  researchers) / Tech stack pills / Team (leadership + 17 contributors) /
  Contact card (Project Director direct email).
- **Theme:** persisted in `localStorage` as `vitos-theme`.
- **Fonts:** Orbitron (display), JetBrains Mono (code), Inter (body) — Google
  Fonts CDN.
- **Three.js:** v0.163.0 via unpkg, ES module import map.
- **VIT Bhopal logo:** local file `vit-bhopal-logo.png` (badge top-right).

## Editing

Everything is in `index.html`. CSS is in a single `<style>` block, theme tokens
are CSS custom properties on `:root[data-theme="dark|light"]`. To change colors,
edit the two `:root[data-theme=…]` blocks at the top.
