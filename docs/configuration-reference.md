# Configuration Reference

Complete reference for every configurable value in this setup.
All user-facing settings live in a single `.env` file at the project root.

---

## `.env` Variables

Copy `env.example` to `.env` before starting Immich. Never commit `.env` to git — it contains secrets.

### Core Paths

| Variable | Default | Required | Description |
|---|---|---|---|
| `UPLOAD_LOCATION` | `./library` | Yes | Absolute path where Immich stores photos, videos, and DB backups. Must have plenty of disk space. Example: `D:\immich-library` |
| `DB_DATA_LOCATION` | `./postgres` | Yes | Absolute path where PostgreSQL stores its data files. Use a local SSD — network shares and USB drives are not supported. |

> **Important**: Both paths are mounted into Docker containers as volumes. If you move them after first run, you must update `.env` and restart — the data moves with the folder, not with the container.

---

### Immich Version

| Variable | Default | Description |
|---|---|---|
| `IMMICH_VERSION` | `v2.6.3` | The Immich release to run. Pin this to a specific version for stability. To upgrade, change the value and run `docker compose pull && docker compose up -d`. See [releases](https://github.com/immich-app/immich/releases). |

---

### Timezone

| Variable | Default | Description |
|---|---|---|
| `TZ` | `Etc/UTC` | Your timezone in tz database format (e.g., `America/New_York`, `Europe/London`, `Asia/Dhaka`). Affects timestamps on photos and log entries. Full list: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones |

---

### Database Credentials

PostgreSQL credentials used internally between Immich and its database container. These never need to be entered by users — they are only used for container-to-container communication.

| Variable | Default | Description |
|---|---|---|
| `DB_PASSWORD` | `CHANGE_ME_use_a_32char_random_string` | **Must be changed** before first run. Use only characters `A-Za-z0-9` — special characters and spaces break the connection string. Generate one: `openssl rand -base64 24` |
| `DB_USERNAME` | `immich` | PostgreSQL username. No need to change. |
| `DB_DATABASE_NAME` | `immich` | PostgreSQL database name. No need to change. |

---

### AWS S3 Glacier Backup

Only required if you are using the `backup-glacier` service. See [aws-glacier-setup.md](aws-glacier-setup.md) for how to create these credentials.

| Variable | Default | Description |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | _(none)_ | IAM user access key ID. Created in the AWS Console → IAM → Users → Security credentials. |
| `AWS_SECRET_ACCESS_KEY` | _(none)_ | IAM user secret key. Shown only once at creation — store it immediately. |
| `S3_BUCKET_NAME` | _(none)_ | Name of the S3 bucket (e.g., `yourname-immich-backup-2026`). Must already exist. |
| `S3_REGION` | `us-east-1` | AWS region where the bucket was created (e.g., `eu-central-1`, `ap-southeast-1`). Must match the bucket's actual region. |

---

## Docker Compose Services

These are defined in `docker-compose.yml` and are not in `.env`. Change them directly in the compose file.

### `immich-server`

| Setting | Current value | Description |
|---|---|---|
| Image | `ghcr.io/immich-app/immich-server:${IMMICH_VERSION}` | Main application and REST API |
| Port | `2283:2283` | Exposes the UI and API on port 2283 of the host |
| Memory limit | `1536M` | Caps RSS to prevent OOM on systems with limited RAM. Increase if you have more than 16 GB. |
| Restart policy | `always` | Starts automatically after Docker Desktop restarts |

### `immich-machine-learning`

Runs smart search (CLIP), face detection, and scene classification.

| Setting | Current value | Description |
|---|---|---|
| Image | `ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION}` | CPU build (no GPU dependencies) |
| `MACHINE_LEARNING_MODEL_TTL` | `60` | Seconds of inactivity before models are unloaded. Frees 1–2 GB RAM when idle. Set to `0` to keep models loaded permanently. |
| `MACHINE_LEARNING_MODEL_TTL_POLL_S` | `10` | How often (seconds) to check the TTL. |
| `MACHINE_LEARNING_WORKERS` | `1` | Number of model runner processes. `1` avoids loading the model multiple times into RAM. Increase only if you have many concurrent users. |
| Memory limit | `4G` | CLIP + face models together use ~2–3 GB. Reduce to `2G` on memory-constrained machines (smart search will still work, slower). |

### `redis` (Valkey)

Used as a task queue and session cache. No user configuration needed.

| Setting | Current value | Description |
|---|---|---|
| Image | `valkey/valkey:8-bookworm` (pinned digest) | Drop-in Redis replacement. Pinned to a specific digest for reproducibility. |
| `--maxmemory` | `128mb` | Maximum RAM for the cache. Raise to `256mb` if you have hundreds of concurrent jobs queued. |
| `--maxmemory-policy` | `allkeys-lru` | Evicts least-recently-used keys when the limit is hit. Correct policy for a job queue. |
| Persistence | Disabled (`--save ""`, `--appendonly no`) | No disk writes — cache is ephemeral by design. |

### `database`

PostgreSQL with the pgvecto.rs extension (used for semantic/vector search).

| Setting | Description |
|---|---|
| Image | `ghcr.io/immich-app/postgres:14-vectorchord0.3.0` — Immich-maintained image with pgvecto.rs pre-installed |
| Data volume | `DB_DATA_LOCATION` from `.env` |
| Health check | TCP connect on port 5432; Immich waits for healthy before starting |

### `backup-glacier`

| Setting | Current value | Description |
|---|---|---|
| Image | `rclone/rclone:1.69` | Minimal Alpine image with rclone. Pinned major version for stability. |
| Cron time | `03:00` daily | Defined in `scripts/backup-entrypoint.sh`. Change `CRON_TIME` there to adjust. |
| Log path | `/logs/glacier-<timestamp>.log` | Mapped to `./logs/` on the host |
| Catch-up threshold | 24 hours | If the container restarts and the last sync was >24 h ago, it syncs immediately on startup. |

---

## rclone Configuration

`config/rclone.conf` configures rclone's S3 connection. Normally you do not need to edit this.

| Key | Value | Description |
|---|---|---|
| `type` | `s3` | S3-compatible backend |
| `provider` | `AWS` | Amazon S3 |
| `env_auth` | `true` | Reads `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` from environment variables injected by Docker |
| `region` | `${S3_REGION}` | Substituted at runtime from the environment variable |
| `storage_class` | `DEEP_ARCHIVE` | Writes all objects directly to Glacier Deep Archive storage class |
| `chunk_size` | `128Mi` | Multipart upload chunk size. 128 MB is optimal for large video files. |
| `upload_concurrency` | `4` | Parallel upload threads per file. Balanced for home upload speeds. |
| `no_check_bucket` | `false` | Verifies the bucket exists before uploading. Set `true` only if you have strict IAM restrictions on `s3:ListBucket`. |

---

## GPU Acceleration

Defined in `hwaccel.ml.yml` and `hwaccel.transcoding.yml`. The current setup uses CPU-only ML and CPU transcoding because ROCm (AMD) does not work on Docker Desktop WSL2.

### Machine Learning backends (`hwaccel.ml.yml`)

| Service key | Hardware | How to enable |
|---|---|---|
| `cpu` | CPU (any) | **Current default** — no changes needed |
| `cuda` | NVIDIA GPU | Change `extends.service` to `cuda` in `docker-compose.yml` |
| `rocm` | AMD GPU (native Linux) | Change `extends.service` to `rocm` |
| `openvino` | Intel GPU / iGPU (Linux) | Change `extends.service` to `openvino` |
| `openvino-wsl` | Intel GPU (WSL2) | Change `extends.service` to `openvino-wsl` |
| `armnn` | ARM Mali GPU | Change `extends.service` to `armnn`; add Mali firmware volumes |
| `rknn` | Rockchip NPU | Change `extends.service` to `rknn` |

### Transcoding backends (`hwaccel.transcoding.yml`)

Uncomment the `extends` block in the `immich-server` service in `docker-compose.yml`.

| Service key | Hardware | Notes |
|---|---|---|
| `nvenc` | NVIDIA (NVENC) | Best option for NVIDIA GPUs |
| `vaapi` | Intel/AMD GPU (native Linux) | For native Linux with `/dev/dri` exposed |
| `vaapi-wsl` | AMD/Intel GPU (WSL2) | Uses DX12→VAAPI bridge |
| `rkmpp` | Rockchip (RKMPP) | Arm SBCs |
| `quicksync` | Intel QuickSync (native Linux) | |

---

## `backup-glacier.sh` Parameters

The sync script accepts runtime behaviour via environment variables (set in `.env` or in `docker-compose.yml`):

| Variable | Default | Description |
|---|---|---|
| `S3_BUCKET_NAME` | _(required)_ | Target S3 bucket |
| `S3_REGION` | `us-east-1` | AWS region |

rclone flags used during sync:

| Flag | Value | Description |
|---|---|---|
| `--transfers` | `4` | Parallel file transfers |
| `--checkers` | `8` | Parallel checksum workers |
| `--contimeout` | `60s` | TCP connection timeout |
| `--timeout` | `300s` | Idle transfer timeout before giving up |
| `--retries` | `3` | Top-level retry attempts per file |
| `--low-level-retries` | `10` | HTTP-level retries per request |
| `--stats` | `60s` | Progress reporting interval |
| `--log-level` | `INFO` | Verbosity (`DEBUG`, `INFO`, `NOTICE`, `ERROR`) |
