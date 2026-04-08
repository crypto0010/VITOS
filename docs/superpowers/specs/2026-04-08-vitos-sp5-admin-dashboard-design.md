# VITOS SP5 — Admin Web Dashboard

**Date:** 2026-04-08
**Status:** SHIPPED in v1.0.0
**Developed by:** Cybersecurity and Digital Forensics Lab, VIT Bhopal University. Project Director: Dr. Hemraj Shobharam Lamkuche. Chief Mentor: Pon Harshavardhanan. Full team in [`AUTHORS.md`](../../../AUTHORS.md). Contact: `vitbhopal.os@gmail.com`.
**Sub-project:** SP5 of 6 (replaces the temporary `vitosctl` CLI shipped in v1)
**Parent spec:** `2026-04-07-vitos-sp1-base-iso-design.md` (VITOS v1, shipped 2026-04-08)
**Predecessor:** SP1–SP4 collapsed into VITOS v1. Only SP6 remains after this.

---

## 1. Goal

Replace the temporary `vitosctl` CLI (shipped in v1 as the admin interface) with a real **web-based VITOS Admin Console** that faculty can open in any browser on the lab network. After SP5 ships, an authorized `vitos-admins` user logs into `https://<lab-host>:8443/`, sees the live student roster, real-time risk scores from the AI engine, network and process maps, and can freeze, isolate, or report on any student session in one click.

The PDF screenshot for the admin console (page 5–6 of `main.pdf`) is the visual target. SP5 implements that screen exactly: students online, risk-coloured rows, live terminal view, network map, kill/isolate/warn/report buttons, and the AI Insight panel.

## 2. Non-goals

- Mobile-friendly responsive layout — desktop browsers only (lab workstations).
- Multi-tenancy / multi-lab — single-lab installation. SP6 considers cross-lab.
- Public internet exposure — bind to lab VLAN only.
- Replacing `vitosctl`. The CLI stays as a fallback / scripting interface; the web dashboard is built **on top of** the same `/var/log/vitos/alerts.jsonl` and `vitos-busd` event bus that `vitosctl` reads.
- Any change to the AI engine, telemetry collectors, or kernel. SP5 is *consume only*.

## 3. Deliverables

1. A new Debian source package **`vitos-dashboard`** living at `vitos-v1/packages/vitos-dashboard/` and built into the v1 ISO via the existing `live-build` pipeline.
2. **Backend:** FastAPI (Python 3.11+) under `/usr/lib/vitos/dashboard/backend/`, served by `uvicorn` from a `vitos-dashboard.service` systemd unit. Listens on `127.0.0.1:8443` only — `nginx` or `caddy` (whichever is in the Kali base) terminates TLS on the lab VLAN interface.
3. **Frontend:** A pre-built React 18 + Vite + TypeScript SPA bundle, statically served by FastAPI from `/usr/share/vitos/dashboard/web/`. **No node_modules in the chroot** — the bundle is built inside the CI container with `npm ci && vite build`, then shipped as static files. Tailwind CSS for styling (no design system to maintain).
4. **Auth:** PAM via `python-pam` against the `vitos-admins` group. Falls back to LDAP/FreeIPA when SP6 lands. Session cookie, HTTP-only, SameSite=Strict, 8 h expiry, server-side store in SQLite at `/var/lib/vitos/dashboard/sessions.db`.
5. **Live data wire:** Server-Sent Events (SSE) endpoint `/api/stream/alerts` pushes new lines from `/var/log/vitos/alerts.jsonl` as they appear. Frontend subscribes once on mount; auto-reconnects on disconnect with exponential backoff.
6. **Live terminal view:** ttyd (in Kali main) reverse-proxied via FastAPI websocket forwarding. Each student's tmux session is exposed as a read-only ttyd instance scoped to the student namespace; admin can attach in read-only or read-write mode (with consent banner shown to the student).
7. **Updated `vitos-monitor` package** to depend on `vitos-dashboard` and to drop the `vitosctl`-as-default suggestion in the README.
8. **Smoke test extension:** the existing `tests/smoke-test.sh` adds 4 new assertions: dashboard service active, `/api/health` returns 200, login form renders, SSE stream emits a heartbeat within 5 s.

## 4. Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Browser on lab workstation                                  │
│  https://lab-host.local:8443/                                │
└──────────────────────────────┬───────────────────────────────┘
                               │ TLS (self-signed in v1, ACME later)
                               ▼
┌──────────────────────────────────────────────────────────────┐
│  caddy (or nginx) — TLS termination, lab VLAN bind only      │
└──────────────────────────────┬───────────────────────────────┘
                               │ http://127.0.0.1:8443/
                               ▼
┌──────────────────────────────────────────────────────────────┐
│  vitos-dashboard.service (FastAPI / uvicorn, user vitos-mon) │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐    │
│  │ Static SPA   │  │ REST API     │  │ SSE / WebSocket  │    │
│  │ /index.html  │  │ /api/...     │  │ /api/stream/...  │    │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────────┘    │
│         │                 │                 │                │
│         └─────────────────┴─────────────────┘                │
│                           │                                  │
│                           ▼                                  │
│  Adapters:                                                   │
│   • alerts_log_tail.py   → tail /var/log/vitos/alerts.jsonl  │
│   • events_bus_sub.py    → connect /run/vitos/bus.sock.sub2  │
│   • vitosctl_shim.py     → exec vitosctl session ... commands│
│   • pam_auth.py          → python-pam against vitos-admins   │
│   • ttyd_proxy.py        → reverse-proxy ttyd ws per session │
└──────────────────────────────────────────────────────────────┘
                               │
                               ▼
            ┌──────────────────────────────┐
            │ vitos-busd (existing, v1)    │
            │ vitos-ai (existing, v1)      │
            │ /var/log/vitos/alerts.jsonl  │
            │ /var/log/vitos/events.jsonl  │
            │ vitosctl (existing, v1)      │
            │ ttyd (one per student tmux)  │
            └──────────────────────────────┘
```

### 4.1 vitos-busd extension (one-line change)

`vitos-busd` currently accepts subscriber connections on `bus.sock.sub`. SP5 needs a *second* concurrent subscriber (the dashboard, in addition to `vitos-ai`). The current code already supports multiple subscribers per `bus.sock.sub` socket via `accept()`-loop. **No code change required** — the dashboard just connects to the same socket.

### 4.2 REST API

| Method | Path | Returns | Auth |
|---|---|---|---|
| `GET`  | `/api/health` | `{ok:true,version,uptime}` | none |
| `POST` | `/api/auth/login` | session cookie | basic body |
| `POST` | `/api/auth/logout` | 204 | session |
| `GET`  | `/api/students` | list of online students with latest risk | session |
| `GET`  | `/api/students/{id}` | per-student detail (history, last 100 events, alerts) | session |
| `GET`  | `/api/sessions` | active student sessions | session |
| `POST` | `/api/sessions/{id}/freeze` | sends SIGSTOP | session |
| `POST` | `/api/sessions/{id}/isolate` | drops the session veth | session |
| `POST` | `/api/sessions/{id}/release` | reverts isolate/freeze | session |
| `GET`  | `/api/sessions/{id}/report` | rendered Markdown report | session |
| `GET`  | `/api/sessions/{id}/report.pdf` | rendered PDF (weasyprint) | session |
| `GET`  | `/api/scopes` | list lab-scope manifests | session |
| `POST` | `/api/scopes/active` | activate a manifest | session |
| `GET`  | `/api/stream/alerts` | SSE: new alerts as they appear | session |
| `GET`  | `/api/stream/events?student=…` | SSE: live event tail per student | session |
| `GET`  | `/api/term/{session_id}/ws` | WS proxy to ttyd | session |

All `POST` actions are logged to `/var/log/vitos/dashboard-audit.jsonl` with `{ts, admin, action, target, result}`.

### 4.3 Frontend pages (React Router routes)

- `/login` — username + password + LDAP toggle (LDAP wired in SP6)
- `/` (Console) — exact reproduction of the PDF mockup: student list (left, scrollable, color-badged by risk), main panel (live terminal embed via xterm.js + ttyd ws), AI Insight panel (bottom, scrolling stream of model rationales for the selected student).
- `/network` — D3-force graph of in-flight connections per student (sourced from eBPF flow events).
- `/process/:sessionId` — process tree (parent→child execve chain from eBPF exec events).
- `/reports/:studentId` — historical alert table + rendered Markdown report + "Download PDF" button.
- `/scopes` — load/activate a lab-exercise scope manifest (textarea + activate button).
- `/audit` — admin action log viewer.

### 4.4 Build pipeline integration

The frontend is built **inside the existing `vitos-builder` Docker image**. SP5 adds Node.js 20 to the builder Dockerfile, runs `npm ci && vite build` in `vitos-v1/packages/vitos-dashboard/web/`, copies the resulting `dist/` into `debian/vitos-dashboard/usr/share/vitos/dashboard/web/`, then `dpkg-buildpackage`. The existing release.yml builds the dashboard package as a fourth matrix entry alongside vitos-base / vitos-tools / vitos-monitor.

## 5. Repository layout (additions only)

```
vitos-v1/packages/vitos-dashboard/
├── debian/
│   ├── control                     # Depends: python3-fastapi, python3-uvicorn, python3-jinja2, python3-pam, ttyd, weasyprint, caddy
│   ├── rules
│   ├── changelog
│   ├── install
│   └── postinst                    # creates sessions.db, generates self-signed TLS cert, enables vitos-dashboard.service + caddy
├── backend/
│   ├── app/
│   │   ├── __init__.py
│   │   ├── main.py                 # FastAPI app, routers
│   │   ├── auth.py                 # PAM + session
│   │   ├── alerts.py               # tail alerts.jsonl + SSE
│   │   ├── events.py               # bus.sock.sub subscriber
│   │   ├── students.py             # roster + per-student
│   │   ├── sessions.py             # freeze/isolate via vitosctl
│   │   ├── reports.py              # markdown + weasyprint PDF
│   │   ├── scopes.py               # lab-scope CRUD
│   │   ├── ttyd_proxy.py           # WS reverse proxy
│   │   └── audit.py                # dashboard-audit.jsonl writer
│   └── tests/
│       ├── test_health.py
│       ├── test_auth.py
│       ├── test_alerts_sse.py
│       └── test_sessions.py
├── web/
│   ├── package.json                # react, vite, tailwind, xterm.js, d3
│   ├── vite.config.ts
│   ├── tailwind.config.ts
│   ├── index.html
│   └── src/
│       ├── main.tsx
│       ├── App.tsx
│       ├── pages/
│       │   ├── Login.tsx
│       │   ├── Console.tsx
│       │   ├── Network.tsx
│       │   ├── Process.tsx
│       │   ├── Reports.tsx
│       │   ├── Scopes.tsx
│       │   └── Audit.tsx
│       ├── components/
│       │   ├── StudentList.tsx
│       │   ├── RiskBadge.tsx
│       │   ├── TerminalEmbed.tsx
│       │   ├── AiInsightPanel.tsx
│       │   └── NetworkMap.tsx
│       ├── lib/
│       │   ├── api.ts              # typed fetch wrapper
│       │   └── sse.ts              # EventSource hook
│       └── styles/
│           └── globals.css
└── systemd/
    ├── vitos-dashboard.service
    └── vitos-dashboard-ttyd@.service   # template, one instance per student session
```

## 6. Smoke-test extensions (4 new assertions, total now 21)

```
say "vitos-dashboard=PASS" if systemctl is-active --quiet vitos-dashboard
curl -sf http://127.0.0.1:8443/api/health  → "ok":true   say "dashboard_health=PASS"
curl -sf -k https://localhost:8443/login    → 200 + form HTML  say "dashboard_login=PASS"
timeout 10 curl -sf -N http://127.0.0.1:8443/api/stream/alerts -H 'Cookie: vitos_test=1'  → ≥1 line  say "dashboard_sse=PASS"
```

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Frontend `npm ci` adds 5–10 min to CI | Cache `~/.npm` between runs via `actions/cache`. |
| ttyd reverse-proxy is fragile (websocket hop) | Bypass via direct ttyd port (`8443+sessionN`) firewalled to localhost; if proxy proves brittle, drop the proxy and surface ttyd's own URL through the API. |
| weasyprint pulls ~150 MB of fonts | Acceptable — Kali base already has DejaVu and Liberation; weasyprint just needs `fonts-noto`. |
| Self-signed TLS cert triggers browser warning every visit | Document the install-cert procedure in the README; SP6 wires ACME against the lab CA. |
| Two admins issuing conflicting `freeze`/`release` actions | Last-write-wins; the audit log captures who did what when. Acceptable for a single-lab tool. |
| Dashboard becomes a covert surveillance amplifier | Same hard rules as v1: actions are advisory, all admin commands are logged, the consent banner is unchanged, students see a banner notifying them when a live terminal view is attached. |

## 8. Out of scope reminders

If during SP5 implementation we feel the urge to add new collectors, change the AI engine, or modify the kernel — **stop**. Those belong to v1 (shipped) or SP6 (next). SP5 is a thin presentation layer over data v1 already produces.
