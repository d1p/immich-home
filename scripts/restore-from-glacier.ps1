# restore-from-glacier.ps1
# Disaster recovery: restores Immich data from Amazon S3 Glacier Deep Archive.
#
# IMPORTANT: Glacier Deep Archive retrieval takes 12-48 hours.
#            Run Step 1 (initiate restore) then wait before running Step 2 (download).
#
# Prerequisites:
#   - AWS CLI installed: https://aws.amazon.com/cli/
#   - AWS credentials configured (same IAM user as backups, or an admin)
#   - Sufficient local disk space (estimate 1.5x your library size for safety)
#
# Usage:
#   # Step 1: Initiate restore from Glacier (starts the 12-48h thaw process)
#   .\restore-from-glacier.ps1 -Initiate -BucketName "your-bucket" -RestoreDays 3
#
#   # Step 2: Download thawed data (run after 12-48 hours)
#   .\restore-from-glacier.ps1 -Download -BucketName "your-bucket" -LocalPath "D:\immich-restore"
#
#   # Check restore status (shows which objects are thawed and ready)
#   .\restore-from-glacier.ps1 -Status -BucketName "your-bucket"

param(
    [switch]$Initiate,
    [switch]$Download,
    [switch]$Status,

    [Parameter(Mandatory = $true)]
    [string]$BucketName,

    [string]$Prefix = "immich",

    [string]$Region = $env:S3_REGION,

    # How many days the thawed copy stays available for download (1-30)
    [int]$RestoreDays = 3,

    # Local path to download restored files into
    [string]$LocalPath = ".\immich-restore"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Validate AWS CLI
# ---------------------------------------------------------------------------
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Error "AWS CLI not found. Install from: https://aws.amazon.com/cli/"
    exit 1
}

if (-not $Region) { $Region = "us-east-1" }

$RegionArgs = @("--region", $Region)

# ---------------------------------------------------------------------------
# STEP 1: Initiate Glacier restore
# ---------------------------------------------------------------------------
if ($Initiate) {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host "STEP 1: Initiating Glacier Deep Archive restore"
    Write-Host "============================================================"
    Write-Host "Bucket : s3://$BucketName/$Prefix"
    Write-Host "Tier   : Bulk (12-48 hours, cheapest)"
    Write-Host "Days   : Thawed copy available for $RestoreDays days"
    Write-Host ""
    Write-Host "Listing objects to restore..."

    $Objects = aws s3api list-objects-v2 `
        --bucket $BucketName `
        --prefix $Prefix `
        --query "Contents[?StorageClass=='DEEP_ARCHIVE'].Key" `
        --output json @RegionArgs | ConvertFrom-Json

    if (-not $Objects -or $Objects.Count -eq 0) {
        Write-Warning "No DEEP_ARCHIVE objects found under s3://$BucketName/$Prefix"
        Write-Host "If the backup ran recently, objects may still be transitioning to DEEP_ARCHIVE."
        exit 0
    }

    Write-Host "Found $($Objects.Count) objects in DEEP_ARCHIVE."
    Write-Host "Initiating restore requests (this may take a few minutes)..."

    $Succeeded = 0
    $Failed    = 0

    foreach ($Key in $Objects) {
        $RestoreRequest = '{"Days":' + $RestoreDays + ',"GlacierJobParameters":{"Tier":"Bulk"}}'
        try {
            aws s3api restore-object `
                --bucket $BucketName `
                --key $Key `
                --restore-request $RestoreRequest `
                @RegionArgs 2>$null
            $Succeeded++
        } catch {
            Write-Warning "Failed to initiate restore for: $Key"
            $Failed++
        }
    }

    Write-Host ""
    Write-Host "Restore initiated: $Succeeded succeeded, $Failed failed."
    Write-Host ""
    Write-Host "============================================================"
    Write-Host "NEXT: Wait 12-48 hours, then run Step 2 to download."
    Write-Host "      Check status with: .\restore-from-glacier.ps1 -Status -BucketName $BucketName"
    Write-Host "============================================================"
    exit 0
}

# ---------------------------------------------------------------------------
# STATUS: Check how many objects are thawed and ready
# ---------------------------------------------------------------------------
if ($Status) {
    Write-Host ""
    Write-Host "Checking restore status for s3://$BucketName/$Prefix ..."

    $Objects = aws s3api list-objects-v2 `
        --bucket $BucketName `
        --prefix $Prefix `
        --query "Contents[?StorageClass=='DEEP_ARCHIVE'].[Key,Restore]" `
        --output json @RegionArgs | ConvertFrom-Json

    $Thawed  = @($Objects | Where-Object { $_[1] -like '*ongoing-request="false"*' })
    $Pending = @($Objects | Where-Object { $_[1] -like '*ongoing-request="true"*' })
    $NotYet  = @($Objects | Where-Object { -not $_[1] })

    Write-Host ""
    Write-Host "Total objects  : $($Objects.Count)"
    Write-Host "Ready to download: $($Thawed.Count)  (restore complete)"
    Write-Host "Thawing (pending): $($Pending.Count) (still in progress)"
    Write-Host "Not yet initiated: $($NotYet.Count)"

    if ($Thawed.Count -eq $Objects.Count) {
        Write-Host ""
        Write-Host "All objects are thawed. Run Step 2 to download."
    } elseif ($Thawed.Count -gt 0) {
        Write-Host ""
        Write-Host "Partial restore complete. Re-check in a few hours."
    }
    exit 0
}

# ---------------------------------------------------------------------------
# STEP 2: Download thawed data
# ---------------------------------------------------------------------------
if ($Download) {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host "STEP 2: Downloading restored data from Glacier"
    Write-Host "============================================================"
    Write-Host "Source : s3://$BucketName/$Prefix"
    Write-Host "Dest   : $LocalPath"
    Write-Host ""

    New-Item -ItemType Directory -Force -Path $LocalPath | Out-Null

    Write-Host "Starting download... (this will take a while for large libraries)"
    aws s3 sync "s3://$BucketName/$Prefix" $LocalPath `
        --force-glacier-transfer `
        @RegionArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Download failed. Check AWS credentials and that objects are fully thawed."
        exit 1
    }

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "Download complete. Files saved to: $LocalPath"
    Write-Host ""
    Write-Host "RESTORE STEPS:"
    Write-Host "  1. Stop Immich:      docker compose down"
    Write-Host "  2. Replace the UPLOAD_LOCATION folder with the downloaded data."
    Write-Host "     The 'backups' subfolder contains DB dump files (.sql.gz)."
    Write-Host "  3. Start Immich:     docker compose up -d"
    Write-Host "  4. Open Immich UI -> Administration -> Maintenance -> Restore"
    Write-Host "     and select the most recent .sql.gz backup file."
    Write-Host "  5. After DB restore, trigger a full library scan:"
    Write-Host "     Administration -> Jobs -> Library -> Scan All"
    Write-Host "============================================================"
    exit 0
}

# No flag provided — show usage
Write-Host "Usage:"
Write-Host "  Step 1 (initiate, wait 12-48h): .\restore-from-glacier.ps1 -Initiate -BucketName <bucket>"
Write-Host "  Status check:                   .\restore-from-glacier.ps1 -Status   -BucketName <bucket>"
Write-Host "  Step 2 (download):              .\restore-from-glacier.ps1 -Download -BucketName <bucket> -LocalPath D:\restore"
