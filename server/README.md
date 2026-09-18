# AOU Hub Server

A self-contained Windows notification server for AOU Hub. It polls sources,
moderates and deduplicates items, and dispatches push notifications, while
running as a real Windows Service with a local English operations dashboard.

> The dashboard/UI language is **English**. The server is a Windows product, not
> a Python script you configure by hand.

---

## One-line install (another Windows PC)

**PowerShell (recommended):**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=\"$env:TEMP\AOUHubInstall.ps1\"; Invoke-WebRequest 'https://raw.githubusercontent.com/ssssoliman937-design/aouapp/main/server/install.ps1' -OutFile $p; & $p -Silent"
```

**CMD:**

```bat
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=\"$env:TEMP\AOUHubInstall.ps1\"; Invoke-WebRequest 'https://raw.githubusercontent.com/ssssoliman937-design/aouapp/main/server/install.ps1' -OutFile $p; & $p -Silent"
```

The bootstrap: detects Windows/arch, elevates if needed, reads `latest.json`,
downloads the Setup, **verifies its SHA-256 (stops on mismatch)**, installs
silently, waits for the service, calls `/health`, and opens the dashboard.

---

## Architecture

| Layer | What |
|---|---|
| `AOUHubServer.exe` | One binary: `run`, `service *`, `dashboard`, `doctor`, `backup`, `enroll`, `import-firebase` |
| Windows Service | `AOUHubServer` - Automatic (Delayed Start), crash-recovery restart |
| Dashboard | English ops UI on `http://127.0.0.1:8787/` (127.0.0.1 only by default) |
| Storage | SQLite (`data/aouhub.db`) with forward-only migrations |
| Secrets | DPAPI-protected blobs under `secrets/` (machine-bound) |
| Cluster | Distributed lease (CAS) - one PRIMARY, standby failover |
| Update | GitHub-hosted `latest.json` + SHA-256 verified Setup |

### Directory layout

```
C:\Program Files\AOU Hub Server\      binaries only (never written at runtime)
  AOUHubServer.exe

C:\ProgramData\AOUHubServer\          all writable runtime data (self-healing)
  data\aouhub.db
  config\config.json
  logs\server.log (+ rotation server.1.log ..)
  cache\  backups\  secrets\  updates\
```

Deleting `logs\` or `cache\` does not break the server - directories self-heal on
every startup; a missing DB is recreated and migrated; a broken config is backed
up and replaced with safe defaults.

---

## Dashboard

Sidebar: **Overview, Sources, Scheduler, Notifications, Moderation, Manual Push,
Cluster, Logs, Backup & Restore, System, Settings.** Dark/Light, responsive,
semantic status (green/amber/red/gray with text + icon, never colour alone).

- **Sources** - health, trust level, last/next check, items, response time,
  expandable diagnostics (states: Healthy / Degraded / Offline / Disabled /
  Auth Required / Rate Limited).
- **Scheduler** - every job's enabled/interval/last-run/duration/result/next-run.
- **Notifications** - queued/sent/failed/skipped/deduplicated + per-category +
  recent history (no raw FCM tokens - delivery is topic-based).
- **Manual Push** - bilingual title/message, category, priority, target, deep
  link, preview, confirm-before-send (every send logged).

---

## Service

```bat
AOUHubServer.exe service install      :: register (Automatic, Delayed Start)
AOUHubServer.exe service start|stop|restart|status|uninstall
```

Recovery: restart after the 1st/2nd/3rd failure (5s / 15s / 60s), daily reset -
no infinite crash loop. Runs without a console, after logout, and after reboot.

---

## Sources & Scheduler

Sources are defined (non-secret) in `config.json`. The scheduler runs polling,
moderation, FCM queue, cleanup and backup jobs; **singleton jobs run only on the
PRIMARY node** so multiple machines never duplicate work.

---

## Firebase / FCM

FCM push uses `firebase-admin` + an enrolled service-account and sends to
**topics** (never stored device tokens). Enroll on each machine:

```bat
AOUHubServer.exe import-firebase C:\path\service-account.json
```

Without a credential the server stays healthy and reports **FCM: Disabled**.
No private key is ever embedded in the exe, Setup, `install.ps1`, `config.json`
or GitHub.

---

## Cluster (multi-machine)

Each install has a persistent random `serverInstanceId` (e.g. `AOU-SRV-7F23A1`,
never a hardware serial). Leadership is a TTL lease acquired by atomic
compare-and-swap; if the primary stops renewing, a standby takes over - only one
primary at a time. Local single-machine store by default; Firebase RTDB REST
store when a database URL + credential are configured.

**Add a server:** Dashboard -> Cluster -> Add Server generates a single-use,
30-minute enrollment code. The new machine installs with `/ENROLL=<code>` and
then imports the Firebase credential locally (DPAPI blobs are machine-bound and
cannot be copied between PCs - security over convenience).

---

## Backup & Restore

Automatic daily backup of database + config + source/moderation data to
`backups\` (7 daily + 4 weekly retention, configurable). **Secrets are never in a
normal backup.** Restore requires explicit confirmation.

```bat
AOUHubServer.exe backup
```

---

## Updates

The server reads `server/latest.json` (version/build/setup_url/sha256/size/
published_at/minimum_windows). The dashboard shows when an update is available;
installation is explicit (never a silent self-replace). Upgrades preserve all
ProgramData.

---

## Doctor / Health

```bat
AOUHubServer.exe doctor          :: PASS / WARNING / FAIL per check + overall
```

`GET /health` returns safe JSON (status, version, instance_id, role, uptime, db,
firebase, sources, last_poll) - never secrets.

---

## Security

- Dashboard binds `127.0.0.1` only; remote access is explicit opt-in
  (`config -> dashboard.remoteEnabled`) and needs your own TLS/reverse-proxy +
  auth. Never `0.0.0.0` by default; no inbound firewall rule created.
- Secrets in DPAPI (machine scope). Logs scrub key/token patterns.

---

## Troubleshooting

| Symptom | Do |
|---|---|
| Dashboard not loading | `AOUHubServer.exe service status`, then `service start` |
| FCM disabled | `import-firebase` a service-account, restart the service |
| Update channel 404 | `latest.json` not published yet |
| Anything red | `AOUHubServer.exe doctor` |

## Uninstall

Uninstall from Apps & Features (or `unins000.exe`). It stops + removes the
service and **asks whether to keep ProgramData (default: keep)**.

---

## Build from source

```powershell
# needs Python 3, PyInstaller, Inno Setup (iscc), pywin32
powershell -File server\build\build.ps1
# -> dist\AOUHubServer\AOUHubServer.exe  +  dist\installer\AOUHubServer-Setup.exe
#    and server\latest.json (sha256/size)
python -m unittest discover -s server\tests   # test suite
```
