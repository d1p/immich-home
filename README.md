# immich-home

Self-hosted photo library running on Windows with Docker Desktop (WSL2 backend).
Google Photos is expensive. A 6TB HDD + Glacier Deep Archive is cheaper and safer.

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

## First-time Setup

### 1. Configure environment

Copy `.env` if it doesn't exist, then edit the values:

```powershell
# Set your timezone, paths, and AWS credentials
notepad .env
```

Key variables:

| Variable | Description |
|---|---|
| `UPLOAD_LOCATION` | Where your photos are stored (e.g. `D:\immich-library`) |
| `DB_DATA_LOCATION` | Where the Postgres data lives (local SSD only, not network share) |
| `IMMICH_VERSION` | Pinned release (e.g. `v2.6.3`) |
| `TZ` | Your timezone (e.g. `Asia/Dhaka`) |
| `DB_PASSWORD` | Pre-generated — change if starting fresh |
| `AWS_ACCESS_KEY_ID` | IAM key for Glacier backups |
| `AWS_SECRET_ACCESS_KEY` | IAM secret for Glacier backups |
| `S3_BUCKET_NAME` | Your S3 bucket (Deep Archive default storage class) |
| `S3_REGION` | AWS region (default: `us-east-1`) |

### 2. Start Immich

```powershell
docker compose up -d
docker compose ps   # all services should be healthy
```

Immich UI: http://localhost:2283

### 3. Enable HTTPS via Tailscale (run once)

Requires Tailscale installed and logged in, with MagicDNS enabled.

```powershell
.\scripts\tailscale-serve.ps1
```

This routes `https://<machine>.<tailnet>.ts.net → http://localhost:2283` with an
auto-provisioned Let's Encrypt certificate. The configuration survives reboots.
To remove: `.\scripts\tailscale-serve.ps1 -Remove`

## Upgrading Immich

1. Check [release notes](https://github.com/immich-app/immich/releases) for breaking changes.
2. Edit `IMMICH_VERSION` in `.env`.
3. Run:

```powershell
docker compose pull
docker compose up -d
```

Immich runs database migrations automatically on startup. If anything goes wrong,
restore from the latest DB backup in `Administration → Maintenance → Restore`.

## Google Photos Import

Import a Google Takeout archive with full duplicate detection. Safe to re-run —
files already in Immich are skipped via checksum comparison.

### Prerequisites

1. Download all Takeout ZIPs from https://takeout.google.com (choose ZIP format).
2. Create an Immich API key: **Account Settings → API Keys → New API Key**.
   Required permissions: `asset.*`, `album.*`, `library.*`, `tag.*`, `person.*`, `job.all`.

### Run import

```powershell
# Dry run first — no files uploaded, just shows what would happen
.\scripts\import-google-photos.ps1 -TakeoutPath "C:\Downloads\takeout-*.zip" -DryRun

# Full import
.\scripts\import-google-photos.ps1 -TakeoutPath "C:\Downloads\takeout-*.zip"
```

`immich-go` is downloaded automatically on first run (single binary, no Node/Docker needed).

What is preserved: original capture dates, GPS locations, descriptions, albums.
What is stacked: RAW+JPEG pairs, burst sequences.
Logs are saved to `./logs/import-<timestamp>.log`.

## Offsite Backup (S3 Glacier Deep Archive)

Daily backup runs automatically at **03:00** via the `backup-glacier` Docker service
(1 hour after Immich's built-in 02:00 DB backup).

**Cost**: ~$1/TB/month. A 200 GB library costs ~$0.20/month to store.

### What is backed up

| Path | Contents |
|---|---|
| `UPLOAD_LOCATION/backups/` | Immich DB dumps (auto-generated daily, 14 retained) |
| `UPLOAD_LOCATION/upload/` | Original uploaded assets **[CRITICAL]** |
| `UPLOAD_LOCATION/library/` | Library assets (storage template) |
| `UPLOAD_LOCATION/profile/` | User profile images |
| `thumbs/`, `encoded-video/` | **Excluded** — regenerable from originals |

### AWS setup (one-time)

> New to AWS? See the full step-by-step guide: [docs/aws-glacier-setup.md](docs/aws-glacier-setup.md)

1. Create an S3 bucket with **Glacier Deep Archive** as the default storage class.
   Enable versioning and add a lifecycle rule to abort incomplete multipart uploads after 7 days.
2. Create an IAM user with a policy granting only:
   `s3:PutObject`, `s3:GetObject`, `s3:ListBucket`, `s3:DeleteObject`, `s3:RestoreObject` — scoped to your bucket.
3. Fill in `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `S3_BUCKET_NAME` in `.env`.

### Manual backup trigger

```powershell
docker compose run --rm backup-glacier
```

Logs are written to `./logs/glacier-<timestamp>.log`.

### Disaster recovery

Glacier Deep Archive retrieval takes **12–48 hours** (Bulk tier). Plan ahead.

```powershell
# Step 1: Initiate thaw (then wait 12-48 hours)
.\scripts\restore-from-glacier.ps1 -Initiate -BucketName "your-bucket-name"

# Check status
.\scripts\restore-from-glacier.ps1 -Status -BucketName "your-bucket-name"

# Step 2: Download thawed data
.\scripts\restore-from-glacier.ps1 -Download -BucketName "your-bucket-name" -LocalPath "D:\immich-restore"
```

After downloading:
1. `docker compose down`
2. Replace `UPLOAD_LOCATION` with the restored data.
3. `docker compose up -d`
4. Restore DB: **Administration → Maintenance → Restore** → pick latest `.sql.gz`.
5. Rescan library: **Administration → Jobs → Library → Scan All**.

## Backup Strategy (3-2-1)

| Copy | Location | Method |
|---|---|---|
| 1 — Primary | Local disk (`UPLOAD_LOCATION`) | Live Immich data |
| 2 — Local DB | `UPLOAD_LOCATION/backups/` | Immich auto-backup (daily, 14 retained) |
| 3 — Offsite | S3 Glacier Deep Archive | `backup-glacier` service (daily at 03:00) |
