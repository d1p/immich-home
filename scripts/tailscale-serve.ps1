# tailscale-serve.ps1
# Configures Tailscale to serve Immich over HTTPS using MagicDNS.
#
# Prerequisites:
#   1. Tailscale is installed and logged in on this machine.
#   2. MagicDNS is enabled in your Tailscale admin console:
#      https://login.tailscale.com/admin/dns
#   3. Immich is running (docker compose up -d).
#
# What this does:
#   - Routes https://<machine-name>.<tailnet>.ts.net  ->  http://localhost:2283
#   - Let's Encrypt cert is provisioned and renewed automatically by Tailscale.
#   - Traffic is end-to-end encrypted via WireGuard (Tailscale).
#
# Run once after machine setup. The configuration persists across reboots.
# To remove: tailscale serve --https=443 off

param(
    [int]$ImmichPort = 2283,
    [switch]$Remove
)

function Test-TailscaleInstalled {
    return $null -ne (Get-Command tailscale -ErrorAction SilentlyContinue)
}

function Get-TailscaleStatus {
    return tailscale status --json | ConvertFrom-Json
}

if (-not (Test-TailscaleInstalled)) {
    Write-Error "Tailscale is not installed or not in PATH. Install from https://tailscale.com/download"
    exit 1
}

$status = Get-TailscaleStatus
if (-not $status.BackendState -eq "Running") {
    Write-Error "Tailscale is not running. Start it and log in first."
    exit 1
}

if ($Remove) {
    Write-Host "Removing Tailscale HTTPS serve for port 443..."
    tailscale serve --https=443 off
    Write-Host "Done. Tailscale HTTPS serve removed."
    exit 0
}

Write-Host "Configuring Tailscale HTTPS serve..."
Write-Host "  Routing: https://<machine>.<tailnet>.ts.net -> http://localhost:$ImmichPort"

tailscale serve --https=443 "http://localhost:$ImmichPort"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to configure Tailscale serve. Check that Tailscale is logged in and MagicDNS is enabled."
    exit 1
}

Write-Host ""
Write-Host "Success! Immich is now accessible at:"

$selfNode = $status.Self
$dnsName  = $selfNode.DNSName.TrimEnd('.')
Write-Host "  https://$dnsName"
Write-Host ""
Write-Host "Note: The certificate is provisioned by Tailscale automatically."
Write-Host "      This configuration persists across reboots."
Write-Host "      To remove: .\tailscale-serve.ps1 -Remove"
