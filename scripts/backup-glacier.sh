#!/bin/sh
# backup-glacier.sh
# Syncs Immich originals and DB backups to Amazon S3 Glacier Deep Archive.
# Invoked by the backup-glacier Docker service daily at 03:00.
# Can be triggered manually: docker compose run --rm backup-glacier
#
# What is synced:
#   /immich-data/upload/   — original uploaded assets (CRITICAL)
#   /immich-data/library/  — library assets (storage template)
#   /immich-data/profile/  — user profile images
#   /immich-data/backups/  — Immich auto-generated daily DB dumps
#
# What is excluded (regenerable, saves storage cost):
#   thumbs/, encoded-video/

set -e

BUCKET="${S3_BUCKET_NAME:-}"
REGION="${S3_REGION:-us-east-1}"

if [ -z "$BUCKET" ]; then
  echo "ERROR: S3_BUCKET_NAME is not set. Aborting backup."
  exit 1
fi

LOG_FILE="/logs/glacier-$(date +%Y%m%d-%H%M%S).log"
REMOTE="s3-glacier:${BUCKET}/immich"

echo "====================================================" | tee -a "$LOG_FILE"
echo "Glacier sync started: $(date)"                        | tee -a "$LOG_FILE"
echo "Destination: ${REMOTE}"                               | tee -a "$LOG_FILE"
echo "====================================================" | tee -a "$LOG_FILE"

# --- Sync each important directory individually for clear logging ---

for DIR in upload library profile backups; do
  SRC="/immich-data/${DIR}"
  if [ -d "$SRC" ]; then
    echo "" | tee -a "$LOG_FILE"
    echo "Syncing ${DIR}/ ..." | tee -a "$LOG_FILE"
    rclone sync "$SRC" "${REMOTE}/${DIR}" \
      --config /config/rclone/rclone.conf \
      --s3-region "$REGION" \
      --transfers 4 \
      --checkers 8 \
      --contimeout 60s \
      --timeout 300s \
      --retries 3 \
      --low-level-retries 10 \
      --stats 60s \
      --log-file "$LOG_FILE" \
      --log-level INFO \
      2>&1 | tee -a "$LOG_FILE"
    echo "Done: ${DIR}/" | tee -a "$LOG_FILE"
  else
    echo "Skipping ${DIR}/ (directory does not exist yet)" | tee -a "$LOG_FILE"
  fi
done

echo "" | tee -a "$LOG_FILE"
echo "====================================================" | tee -a "$LOG_FILE"
echo "Glacier sync completed: $(date)"                      | tee -a "$LOG_FILE"
echo "====================================================" | tee -a "$LOG_FILE"

# Record successful completion timestamp for startup catch-up logic
date +%s > /logs/.last-sync-success
echo "Success marker written: $(date)" | tee -a "$LOG_FILE"
