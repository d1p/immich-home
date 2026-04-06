# Google Photos Import

This guide explains how to move your entire Google Photos library into Immich, preserving albums, capture dates, GPS locations, and descriptions.

**Time needed**: 30–60 minutes of setup; the actual upload runs unattended and may take hours depending on library size and internet speed.

---

## How It Works

The script uses **immich-go**, an open-source tool designed specifically for this task.
It reads Google Takeout ZIP files directly (no extraction needed) and uploads to Immich via the API.

- **Duplicate detection**: every file is checksummed against your existing Immich library. If you already uploaded something, it is skipped — safe to re-run.
- **Albums**: Google Photos albums are recreated in Immich automatically.
- **Metadata preserved**: original capture dates, GPS coordinates, descriptions.
- **RAW+JPEG pairs**: stacked so the JPEG is shown as the cover.
- **Burst sequences**: grouped into stacks.

`immich-go.exe` is downloaded automatically on first run (a single ~20 MB binary, no Node.js or Docker required).

---

## Step 1 — Export from Google Photos

1. Go to https://takeout.google.com
2. Click **Deselect all**, then scroll down and check only **Google Photos**
3. Click **Next step**
4. Choose:
   - **Delivery method**: Send download link via email (or Add to Drive)
   - **Frequency**: Export once
   - **File type**: `.zip`
   - **File size**: 10 GB recommended (creates multiple ZIPs for large libraries)
5. Click **Create export**

Google will email you a download link within minutes to several hours, depending on library size.

Download all the ZIP files. You do not need to extract them.

---

## Step 2 — Create an Immich API Key

1. Log in to Immich
2. Click your avatar (top right) → **Account Settings** → **API Keys**
3. Click **New API Key**
4. Give it a name (e.g., `google-import`)
5. Grant the following permissions (or select all):
   - `asset.read`, `asset.write`, `asset.delete`, `asset.copy`
   - `album.read`, `album.write`
   - `library.read`, `library.write`
   - `tag.read`, `tag.write`
   - `person.read`, `person.write`
   - `job.all`
6. Click **Create** and copy the key — you'll only see it once

---

## Step 3 — Run the Import

Open PowerShell in the project folder. Run a dry run first to see what would happen without uploading anything:

```powershell
.\scripts\import-google-photos.ps1 -TakeoutPath "C:\Downloads\takeout-*.zip" -DryRun
```

If the output looks correct, run the full import:

```powershell
.\scripts\import-google-photos.ps1 -TakeoutPath "C:\Downloads\takeout-*.zip"
```

The script will prompt for your API key if it is not set. You can also set it beforehand:

```powershell
$env:IMMICH_API_KEY = "your-api-key-here"
.\scripts\import-google-photos.ps1 -TakeoutPath "C:\Downloads\takeout-*.zip"
```

---

## Script Parameters

| Parameter | Default | Required | Description |
|---|---|---|---|
| `-TakeoutPath` | _(none)_ | **Yes** | Path or glob to your Takeout ZIPs. Examples: `"C:\Downloads\takeout-*.zip"` or `"C:\Downloads\takeout-2024\"` |
| `-ImmichUrl` | `http://localhost:2283` | No | Immich base URL. Change if Immich is running on another machine or port. |
| `-ApiKey` | `$env:IMMICH_API_KEY` | No | Immich API key. If not provided, the script prompts interactively. |
| `-DryRun` | `false` | No | If set, shows what would be imported without uploading anything. Always run this first on a large library. |
| `-ConcurrentTasks` | `8` | No | Parallel upload workers. Reduce to `4` on slow connections or if Immich becomes unresponsive. |
| `-ImmichGoVersion` | `v0.31.0` | No | Version of immich-go to download. Check https://github.com/simulot/immich-go/releases for newer versions. |

---

## What Gets Imported

| Data | Preserved? |
|---|---|
| Original photo/video files | ✅ Yes |
| Original capture date/time | ✅ Yes (from JSON sidecar) |
| GPS location | ✅ Yes |
| Description/caption | ✅ Yes |
| Albums | ✅ Yes — recreated in Immich |
| RAW+JPEG pairs | ✅ Stacked (JPEG shown as cover) |
| Burst sequences | ✅ Stacked |
| Shared albums (received) | ⚠️ Takeout only includes albums you own |
| "Favourites" / star | ❌ Not yet supported by immich-go |

---

## Monitoring Progress

The script logs to `./logs/import-<timestamp>.log`.

To watch the log live in another terminal:

```powershell
Get-Content .\logs\import-*.log -Tail 20 -Wait
```

You can also watch the upload progress in Immich's admin panel:
**Administration → Jobs**

---

## Resuming an Interrupted Import

The import is safe to interrupt and re-run at any time.

When you re-run, immich-go checksums every local file against what is already in Immich. Files that were successfully uploaded are skipped. Only new or failed files are uploaded again.

---

## Troubleshooting

**"Cannot reach Immich at http://localhost:2283"**  
Make sure Immich is running: `docker compose ps`. All services should be healthy.

**Some photos are missing**  
Google Takeout sometimes omits photos from exports. Export again and check you selected all date ranges. Running the script again on a second Takeout archive will upload only the missing files.

**Dates are wrong after import**  
This usually means the JSON sidecar file was missing from the Takeout export. You can correct dates manually in Immich by selecting photos and editing metadata.

**Import is very slow**  
Reduce `-ConcurrentTasks` to ease load on Immich, or run during off-peak hours. Processing (thumbnail generation, face detection) happens after upload and may make Immich feel slower — that is normal.
