# import-google-photos.ps1
# Imports a Google Photos Takeout archive into Immich with duplicate detection.
#
# Usage:
#   .\import-google-photos.ps1 -TakeoutPath "C:\Downloads\takeout-*.zip"
#   .\import-google-photos.ps1 -TakeoutPath "C:\Downloads\takeout-*.zip" -DryRun
#   .\import-google-photos.ps1 -TakeoutPath "C:\Downloads" -ImmichUrl "http://192.168.1.50:2283"
#
# What this does:
#   - Downloads immich-go.exe automatically if not present (single binary, no Node/Docker needed)
#   - Reads Google Takeout ZIPs directly -- no extraction needed
#   - Preserves: albums, descriptions, GPS locations, original capture dates
#   - Duplicate detection: checksums all files against Immich; skips any already uploaded
#   - Safe to re-run: subsequent runs upload 0 new photos if nothing changed
#   - Groups RAW+JPEG pairs and burst shots into stacks
#   - Pauses Immich background jobs during import for faster upload
#   - Logs to ./logs/import-<timestamp>.log
#
# Prerequisites:
#   - Immich is running (docker compose up -d)
#   - Create an API key in Immich: Account Settings -> API Keys -> New API Key
#     The key needs: asset.read, asset.write, asset.delete, asset.copy,
#                    album.read, album.write, library.read, library.write,
#                    tag.read, tag.write, person.read, person.write, job.all
#   - Google Takeout ZIPs downloaded from https://takeout.google.com

param(
    [Parameter(Mandatory = $true)]
    [string]$TakeoutPath,

    [string]$ImmichUrl = "http://localhost:2283",

    [string]$ApiKey = $env:IMMICH_API_KEY,

    [switch]$DryRun,

    [int]$ConcurrentTasks = 8,

    [string]$ImmichGoVersion = "v0.31.0"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Setup directories
# ---------------------------------------------------------------------------
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir    = Split-Path -Parent $ScriptDir
$LogDir     = Join-Path $RootDir "logs"
$BinDir     = Join-Path $RootDir ".bin"
$Timestamp  = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile    = Join-Path $LogDir "import-$Timestamp.log"

New-Item -ItemType Directory -Force -Path $LogDir  | Out-Null
New-Item -ItemType Directory -Force -Path $BinDir  | Out-Null

# ---------------------------------------------------------------------------
# Prompt for API key if not provided
# ---------------------------------------------------------------------------
if (-not $ApiKey) {
    Write-Host ""
    Write-Host "Immich API key not set. Create one in Immich:"
    Write-Host "  Account Settings -> API Keys -> New API Key"
    Write-Host ""
    $SecureKey = Read-Host "Enter your Immich API key" -AsSecureString
    $ApiKey    = [System.Net.NetworkCredential]::new("", $SecureKey).Password
}

if (-not $ApiKey) {
    Write-Error "API key is required. Set IMMICH_API_KEY env var or pass -ApiKey."
    exit 1
}

# ---------------------------------------------------------------------------
# Download immich-go if not present
# ---------------------------------------------------------------------------
$ImmichGoExe = Join-Path $BinDir "immich-go.exe"

if (-not (Test-Path $ImmichGoExe)) {
    Write-Host "Downloading immich-go $ImmichGoVersion..."
    $DownloadUrl = "https://github.com/simulot/immich-go/releases/download/$ImmichGoVersion/immich-go_Windows_x86_64.zip"
    $ZipPath     = Join-Path $BinDir "immich-go.zip"

    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing
        Expand-Archive -Path $ZipPath -DestinationPath $BinDir -Force
        Remove-Item $ZipPath -ErrorAction SilentlyContinue
        Write-Host "immich-go downloaded to $ImmichGoExe"
    } catch {
        Write-Error "Failed to download immich-go: $_`nDownload manually from: https://github.com/simulot/immich-go/releases/tag/$ImmichGoVersion"
        exit 1
    }
}

if (-not (Test-Path $ImmichGoExe)) {
    Write-Error "immich-go.exe not found at '$ImmichGoExe' after download. Check the archive contents."
    exit 1
}

# ---------------------------------------------------------------------------
# Validate that Immich is reachable
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Checking Immich connectivity at $ImmichUrl..."
try {
    $Response = Invoke-WebRequest -Uri "$ImmichUrl/api/server/ping" -UseBasicParsing -TimeoutSec 10
    if ($Response.StatusCode -ne 200) { throw "Unexpected status: $($Response.StatusCode)" }
    Write-Host "  Immich is reachable."
} catch {
    Write-Error "Cannot reach Immich at $ImmichUrl. Make sure it is running (docker compose up -d)."
    exit 1
}

# ---------------------------------------------------------------------------
# Resolve the takeout path glob
# ---------------------------------------------------------------------------
$TakeoutItems = @(Resolve-Path $TakeoutPath -ErrorAction SilentlyContinue)

if ($TakeoutItems.Count -eq 0) {
    Write-Error "No files found matching: $TakeoutPath"
    exit 1
}

Write-Host ""
Write-Host "Found $($TakeoutItems.Count) takeout item(s):"
$TakeoutItems | ForEach-Object { Write-Host "  $_" }

# ---------------------------------------------------------------------------
# Build immich-go arguments
# ---------------------------------------------------------------------------
$GoArgs = @(
    "upload",
    "from-google-photos",
    "--server=$ImmichUrl",
    "--api-key=$ApiKey",
    "--concurrent-tasks=$ConcurrentTasks",
    "--sync-albums",                    # Recreate Google Photos albums in Immich
    "--manage-burst=Stack",             # Stack burst photo sequences
    "--manage-raw-jpeg=StackCoverJPG",  # Stack RAW+JPEG, show JPEG as cover
    "--on-errors=continue",             # Don't stop on individual file errors
    "--session-tag",                    # Tag batch with timestamp for tracking
    "--tag=Source/GooglePhotos",        # Tag all imports for easy filtering
    "--pause-immich-jobs=true",         # Pause thumbnailing during import (faster)
    "--log-level=INFO",
    "--log-file=$LogFile"
)

if ($DryRun) {
    $GoArgs += "--dry-run"
    Write-Host ""
    Write-Host "DRY RUN mode -- no files will be uploaded."
}

# Add all takeout paths as positional arguments
$TakeoutItems | ForEach-Object { $GoArgs += $_.Path }

# ---------------------------------------------------------------------------
# Run import
# ---------------------------------------------------------------------------
Write-Host ""
if ($DryRun) {
    Write-Host "Starting DRY RUN import... ($(Get-Date))"
} else {
    Write-Host "Starting Google Photos import... ($(Get-Date))"
    Write-Host "Log file: $LogFile"
    Write-Host ""
    Write-Host "Duplicate detection: immich-go checksums all local files against your"
    Write-Host "Immich library. Files already uploaded will be skipped automatically."
    Write-Host "This run is safe to interrupt and re-run at any time."
}
Write-Host ""

& $ImmichGoExe @GoArgs
$ExitCode = $LASTEXITCODE

Write-Host ""
Write-Host "====================================================="
if ($ExitCode -eq 0) {
    Write-Host "Import completed successfully. ($(Get-Date))"
} else {
    Write-Host "Import finished with warnings (exit code $ExitCode)."
    Write-Host "Review the log for details: $LogFile"
}
Write-Host "====================================================="
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Open Immich and verify your photos appeared correctly."
Write-Host "  2. Check albums were created from your Google Photos organisation."
Write-Host "  3. Re-run this script anytime -- duplicates are skipped automatically."

exit $ExitCode
