#!/bin/sh
# backup-entrypoint.sh
# Entrypoint for the backup-glacier Docker service.
#
# On every container start (including after reboots / Docker Desktop restarts):
#   1. Reads /logs/.last-sync-success (a Unix timestamp written by backup-glacier.sh).
#   2. If the file is missing, or the last sync was more than 24 hours ago,
#      runs a catch-up sync immediately before entering the cron loop.
#   3. If the last sync was within 24 hours, skips the startup sync.
#
# Then enters a loop that runs a sync every day at 03:00.
# A date guard prevents double-firing if the container is restarted within
# the same minute.

LAST_SYNC_FILE="/logs/.last-sync-success"
SYNC_INTERVAL=86400   # 24 hours in seconds
CRON_TIME="03:00"

# ---------------------------------------------------------------------------
# run_if_missed: check last sync timestamp and catch up if needed
# ---------------------------------------------------------------------------
run_if_missed() {
    echo "=== Startup check ==="

    if [ ! -f "$LAST_SYNC_FILE" ]; then
        echo "No previous sync record found. Running initial sync now..."
        /scripts/backup-glacier.sh
        return
    fi

    LAST=$(cat "$LAST_SYNC_FILE")
    NOW=$(date +%s)
    ELAPSED=$(( NOW - LAST ))
    HOURS=$(( ELAPSED / 3600 ))
    LAST_HUMAN=$(date -d "@$LAST" 2>/dev/null || date -r "$LAST" 2>/dev/null || echo "unknown")

    if [ "$ELAPSED" -gt "$SYNC_INTERVAL" ]; then
        echo "Last sync: ${LAST_HUMAN} (${HOURS}h ago). Threshold exceeded — running catch-up sync..."
        /scripts/backup-glacier.sh
    else
        HOURS_UNTIL=$(( (SYNC_INTERVAL - ELAPSED) / 3600 ))
        echo "Last sync: ${LAST_HUMAN} (${HOURS}h ago). No catch-up needed."
        echo "Next scheduled sync at ${CRON_TIME} (in ~${HOURS_UNTIL}h)."
    fi

    echo "=== Startup check done ==="
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo ""
echo "======================================================"
echo "Glacier backup service starting: $(date)"
echo "======================================================"

run_if_missed

echo ""
echo "Entering cron loop — will sync daily at ${CRON_TIME}."
echo ""

LAST_RUN_DATE=""

while true; do
    CURRENT_TIME=$(date +%H:%M)
    CURRENT_DATE=$(date +%Y-%m-%d)

    # Guard against double-firing: only run once per calendar date at CRON_TIME
    if [ "$CURRENT_TIME" = "$CRON_TIME" ] && [ "$LAST_RUN_DATE" != "$CURRENT_DATE" ]; then
        LAST_RUN_DATE="$CURRENT_DATE"
        echo "Cron: scheduled sync triggered at $(date)"
        /scripts/backup-glacier.sh
        # Sleep past the current minute so we do not re-enter the condition
        sleep 61
    fi

    sleep 30
done
