# VITOS SP5 Implementation Plan — Admin Web Dashboard

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Replace the temporary `vitosctl` CLI shipped in v1 with a FastAPI + React web admin console (matching the PDF mockup) running as a `vitos-dashboard` Debian package, integrated into the existing live-build ISO and CI pipeline.

**Architecture:** New `vitos-dashboard` Debian source package. Backend = FastAPI/uvicorn under systemd, statically serves a Vite-built React SPA, exposes a typed REST + SSE API over the existing `vitos-busd` event bus and `/var/log/vitos/alerts.jsonl`. PAM auth in v1 of SP5; LDAP wired in SP6. ttyd reverse-proxied for live terminal view. caddy terminates TLS on the lab VLAN interface.

**Tech Stack:** Python 3.11, FastAPI, uvicorn, python-pam, ttyd, caddy, weasyprint, Node.js 20, Vite, React 18, TypeScript, Tailwind CSS, xterm.js, D3.

**Spec:** `docs/superpowers/specs/2026-04-08-vitos-sp5-admin-dashboard-design.md`

---

## Tasks

### Task 1: Add Node.js 20 to vitos-builder

**Files:**
- Modify: `vitos-v1/Dockerfile` (add `nodejs npm` from nodesource or kali main)

- [ ] Add `nodejs` (≥ 20) to apt-get install
- [ ] Verify `node --version && npm --version` inside builder
- [ ] Commit

### Task 2: vitos-dashboard package skeleton

**Files:**
- Create: `vitos-v1/packages/vitos-dashboard/debian/{control,rules,changelog,install,postinst}`
- Create: `vitos-v1/packages/vitos-dashboard/backend/app/main.py` (minimal FastAPI app with `/api/health`)
- Create: `vitos-v1/packages/vitos-dashboard/systemd/vitos-dashboard.service`

- [ ] Write debian/control with FastAPI + uvicorn + python-pam + ttyd + caddy + weasyprint deps
- [ ] Write a 20-line FastAPI `main.py` returning `{ok:true,version,uptime}` from `/api/health`
- [ ] Write the systemd unit (User=vitos-mon, ExecStart uvicorn on 127.0.0.1:8443)
- [ ] dpkg-buildpackage smoke test inside builder
- [ ] Commit

### Task 3: PAM authentication

**Files:**
- Create: `backend/app/auth.py`
- Create: `backend/tests/test_auth.py`

- [ ] TDD: write test asserting login with bad creds returns 401
- [ ] TDD: write test asserting login with valid `vitos-admins` user returns session cookie
- [ ] Implement `auth.py` using python-pam against the local PAM stack
- [ ] Server-side session store in SQLite `/var/lib/vitos/dashboard/sessions.db`
- [ ] Add `/api/auth/login`, `/api/auth/logout`, dependency `current_admin`
- [ ] Commit

### Task 4: Alerts log tail + SSE endpoint

**Files:**
- Create: `backend/app/alerts.py`
- Create: `backend/tests/test_alerts_sse.py`

- [ ] TDD: append a line to a temp `alerts.jsonl`, assert SSE client receives it within 1 s
- [ ] Implement async tail using `aiofiles` and an asyncio.Queue per subscriber
- [ ] Wire `/api/stream/alerts` SSE endpoint
- [ ] Commit

### Task 5: Event bus subscriber

**Files:**
- Create: `backend/app/events.py`

- [ ] Connect to `/run/vitos/bus.sock.sub` on startup, parse JSON lines, fan out per-student to in-memory ring (last 1000 events per student)
- [ ] `/api/students/{id}/events` returns the ring; SSE on `/api/stream/events?student=…`
- [ ] Commit

### Task 6: Session control endpoints

**Files:**
- Create: `backend/app/sessions.py`

- [ ] Implement GET `/api/sessions` (list `/run/vitos/sessions/`)
- [ ] Implement POST `/api/sessions/{id}/freeze`, `/isolate`, `/release` by shelling out to `vitosctl session …`
- [ ] Audit log every action to `/var/log/vitos/dashboard-audit.jsonl`
- [ ] Commit

### Task 7: Reports endpoint (Markdown + PDF via weasyprint)

**Files:**
- Create: `backend/app/reports.py`
- Create: `backend/templates/incident-report.html.j2`

- [ ] Reuse `vitosctl report` Markdown output as the data layer
- [ ] Render through Jinja2 → HTML → weasyprint PDF
- [ ] Endpoints `GET /api/sessions/{id}/report` and `…/report.pdf`
- [ ] Commit

### Task 8: ttyd reverse-proxy

**Files:**
- Create: `backend/app/ttyd_proxy.py`
- Create: `vitos-v1/packages/vitos-dashboard/systemd/vitos-dashboard-ttyd@.service`

- [ ] Template unit launches `ttyd -p 7681 -c admin:<dyn> -W tmux attach -t student-%I`
- [ ] FastAPI WS handler proxies bytes between client WS and the ttyd process
- [ ] Read-only mode (`-W` omitted) by default; admin must click "go interactive" to enable write
- [ ] Commit

### Task 9: React frontend scaffold

**Files:**
- Create: `web/{package.json,vite.config.ts,tailwind.config.ts,index.html,tsconfig.json}`
- Create: `web/src/main.tsx`, `web/src/App.tsx`

- [ ] `npm init vite@latest -- --template react-ts`
- [ ] Add tailwind, react-router, swr, xterm.js, d3
- [ ] Hello-world App.tsx renders, `vite build` produces `dist/`
- [ ] Commit

### Task 10: Login page + auth flow

**Files:**
- Create: `web/src/pages/Login.tsx`
- Create: `web/src/lib/api.ts`

- [ ] Login form posts to `/api/auth/login`, stores nothing client-side (cookie-only)
- [ ] Redirect to `/` on success
- [ ] Commit

### Task 11: Console page (matches PDF mockup)

**Files:**
- Create: `web/src/pages/Console.tsx`
- Create: `web/src/components/{StudentList,RiskBadge,TerminalEmbed,AiInsightPanel}.tsx`
- Create: `web/src/lib/sse.ts`

- [ ] StudentList — left rail, scrollable, color-coded risk badges
- [ ] TerminalEmbed — xterm.js connected to `/api/term/{sessionId}/ws`
- [ ] AiInsightPanel — tail of selected student's `ai_reason` from SSE
- [ ] Buttons: Kill, Isolate, Send Warning, Report
- [ ] Commit

### Task 12: Network map page

**Files:**
- Create: `web/src/pages/Network.tsx`, `web/src/components/NetworkMap.tsx`

- [ ] D3 force-directed graph: nodes = student PIDs + remote IPs, edges = active flows
- [ ] Sources data from `/api/stream/events?student=*` filtered to net_flow type
- [ ] Commit

### Task 13: Process tree page

**Files:**
- Create: `web/src/pages/Process.tsx`

- [ ] Render parent→child execve chain from event ring
- [ ] Highlight `setuid`/`sudo` events red
- [ ] Commit

### Task 14: Reports + Scopes + Audit pages

**Files:**
- Create: `web/src/pages/{Reports,Scopes,Audit}.tsx`

- [ ] Reports: per-student alert table + Markdown render + Download PDF
- [ ] Scopes: textarea for YAML manifest + Activate button
- [ ] Audit: paginated `/var/log/vitos/dashboard-audit.jsonl` viewer
- [ ] Commit

### Task 15: Wire frontend build into vitos-dashboard package

**Files:**
- Modify: `vitos-v1/packages/vitos-dashboard/debian/rules`

- [ ] Override `dh_auto_build` to run `cd web && npm ci && vite build && cp -r dist ../debian/vitos-dashboard/usr/share/vitos/dashboard/web/`
- [ ] Verify the .deb contains the `web/dist/` tree
- [ ] Commit

### Task 16: caddy TLS termination

**Files:**
- Create: `vitos-v1/packages/vitos-dashboard/etc/caddy/Caddyfile`

- [ ] Caddy config: lab VLAN bind, self-signed cert, proxy to `127.0.0.1:8443`
- [ ] postinst generates the cert with `openssl req`
- [ ] Commit

### Task 17: CI workflow update

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/release.yml`

- [ ] Add `vitos-dashboard` to the matrix in ci.yml
- [ ] Add the package build to the release.yml `for pkg in …` loop
- [ ] Cache `~/.npm` across runs
- [ ] Commit

### Task 18: Smoke test extensions (4 new assertions)

**Files:**
- Modify: `vitos-v1/packages/vitos-base/usr/lib/vitos/firstboot.sh` (selftest action)

- [ ] Add `vitos-dashboard=PASS|FAIL`, `dashboard_health`, `dashboard_login`, `dashboard_sse`
- [ ] Commit

### Task 19: Trigger release.yml, verify VITOS v1.1 publishes

- [ ] Push, dispatch release workflow
- [ ] Verify ISO size still under the 5×1.9 GB envelope (or rebalance split count)
- [ ] Verify dashboard reachable in QEMU smoke
- [ ] Tag `v1.1.0`

---

## Self-Review Checklist

- [ ] Spec coverage — every section of SP5 design has a task
- [ ] No placeholders — every step has actual code or commands
- [ ] Type consistency — `student_id`/`session_id` field names match v1
- [ ] Out-of-scope — nothing here touches kernel, AI engine, or v1 collectors
