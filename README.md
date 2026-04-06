# immich-home

Self-hosted photo library running on Windows with Docker Desktop (WSL2 backend).
Google Photos is expensive. A 6TB HDD + Glacier Deep Archive is cheaper and safer.

---

## Documentation

| Guide | Audience | Description |
|---|---|---|
| [Getting Started](docs/getting-started.md) | Everyone | Install, configure, and run Immich from scratch |
| [Configuration Reference](docs/configuration-reference.md) | All | Every `.env` variable, Docker service setting, and script parameter |
| [Google Photos Import](docs/google-photos-import.md) | Everyone | Migrate your Google Photos library with duplicate detection |
| [Backup & Recovery](docs/backup-and-recovery.md) | Everyone | Backup strategy, verification, and full disaster recovery |
| [AWS Glacier Setup](docs/aws-glacier-setup.md) | Everyone | Step-by-step: create AWS account, bucket, and IAM credentials |
| [HTTPS Setup](docs/https-setup.md) | Everyone | Enable HTTPS and remote access via Tailscale MagicDNS |

---

## Stack

| Service | Image | Purpose |
|---|---|---|
| `immich-server` | `ghcr.io/immich-app/immich-server:v2.6.3` | Main app + API (port 2283) |
| `immich-machine-learning` | `ghcr.io/immich-app/immich-machine-learning:v2.6.3` | Smart search, face detection (CPU) |
| `database` | `ghcr.io/immich-app/postgres:14-vectorchord0.3.0` | PostgreSQL + pgvectors |
| `redis` | `valkey/valkey:8-bookworm` | Cache / job queues |
| `backup-glacier` | `rclone/rclone:1.69` | Daily offsite sync to S3 Glacier Deep Archive |

**Nginx and Cloudflare Tunnel have been removed.** Immich is exposed directly on port 2283.
HTTPS is provided by Tailscale MagicDNS (`tailscale serve`).

## GPU Acceleration

| Feature | Backend | Reason |
|---|---|---|
| Video transcoding | `vaapi-wsl` (AMD RX 7800 XT) | DirectX 12 → VAAPI bridge works on WSL2 |
| ML (smart search, faces) | CPU | ROCm does not work on Docker Desktop WSL2 |

> **Native Linux upgrade path**: change ML extends to `hwaccel.ml.yml / rocm` and
> transcoding extends to `hwaccel.transcoding.yml / vaapi`. Two-line change.

---

## Quick Start

```powershell
# 1. Copy and fill in the config
Copy-Item env.example .env
notepad .env

# 2. Start
docker compose up -d
docker compose ps   # all services should show healthy

# 3. Open in browser
start http://localhost:2283
```

→ Full walk-through for first timers: [docs/getting-started.md](docs/getting-started.md)

---

## Upgrading Immich

1. Check [release notes](https://github.com/immich-app/immich/releases) for breaking changes.
2. Edit `IMMICH_VERSION` in `.env`.
3. Run:

```powershell
docker compose pull && docker compose up -d
```

Immich runs database migrations automatically on startup.

---

## Common Tasks

| Task | Command / Location |
|---|---|
| Start / stop | `docker compose up -d` / `docker compose down` |
| View logs | `docker compose logs immich-server --tail 50` |
| Trigger manual backup | `docker compose run --rm backup-glacier` |
| Enable HTTPS | `.\scripts\tailscale-serve.ps1` |
| Import Google Photos | `.\scripts\import-google-photos.ps1 -TakeoutPath "C:\Downloads\takeout-*.zip"` |
| Restore from Glacier | See [docs/backup-and-recovery.md](docs/backup-and-recovery.md) |

---

## Backup Strategy (3-2-1)

| Copy | Location | Frequency |
|---|---|---|
| 1 — Primary | Local disk (`UPLOAD_LOCATION`) | Continuous |
| 2 — Local DB | `UPLOAD_LOCATION/backups/` | Daily at 02:00 (Immich built-in) |
| 3 — Offsite | S3 Glacier Deep Archive | Daily at 03:00 (`backup-glacier` service) |

Cost: ~$1/TB/month. A 200 GB library costs ~$0.20/month.

→ [docs/backup-and-recovery.md](docs/backup-and-recovery.md)

