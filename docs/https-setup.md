# HTTPS Setup with Tailscale

By default, Immich is available on your local network at `http://localhost:2283` or `http://192.168.x.x:2283`.

This guide enables:
- A permanent, human-readable address (e.g., `https://yourpc.your-tailnet.ts.net`)
- A valid HTTPS certificate (no browser warnings)
- Access from anywhere in the world, not just your home Wi-Fi
- All traffic encrypted end-to-end via WireGuard

This uses **Tailscale**, which is free for personal use (up to 3 users, 100 devices).

---

## What Is Tailscale?

Tailscale creates a private, encrypted network between all your devices — phone, laptop, home server — without opening any ports on your router. It is simpler and safer than a traditional VPN or port forwarding.

You get a permanent machine address called a **MagicDNS name**: `https://yourpc.your-tailnet.ts.net`

---

## Prerequisites

- [ ] Immich is running (`docker compose up -d`)
- [ ] Tailscale is installed on this PC: https://tailscale.com/download
- [ ] You are logged in to Tailscale on this PC
- [ ] MagicDNS is enabled in your Tailscale admin console

---

## Step 1 — Install Tailscale

Download and install Tailscale from https://tailscale.com/download/windows.

After installing, click the Tailscale tray icon and sign in (or create a free account).

---

## Step 2 — Enable MagicDNS

1. Go to https://login.tailscale.com/admin/dns
2. Under **MagicDNS**, click **Enable MagicDNS** if it isn't already on
3. Under **HTTPS Certificates**, click **Enable** — this allows Tailscale to provision Let's Encrypt certificates for your machines

---

## Step 3 — Run the Setup Script

In PowerShell, from the project folder:

```powershell
.\scripts\tailscale-serve.ps1
```

This runs `tailscale serve --https=443 http://localhost:2283`, which:
- Routes `https://<machine>.<tailnet>.ts.net` → `http://localhost:2283` on this machine
- Provisions a Let's Encrypt certificate automatically
- Configuration persists across reboots — you only need to run this once

The script will print your Immich URL when it succeeds:

```
Success! Immich is now accessible at:
  https://yourpc.your-tailnet.ts.net
```

---

## Step 4 — Access Immich

Visit the URL printed by the script from any device on your Tailscale network.

Install the Tailscale app on your phone to access Immich remotely:
- iOS: https://apps.apple.com/app/tailscale/id1470499037
- Android: https://play.google.com/store/apps/details?id=com.tailscale.ipn.android

---

## Script Parameters

`scripts/tailscale-serve.ps1` accepts the following parameters:

| Parameter | Default | Description |
|---|---|---|
| `-ImmichPort` | `2283` | Local port Immich listens on. Change only if you changed the port in `docker-compose.yml`. |
| `-Remove` | _(switch)_ | Removes the HTTPS serve configuration. Run this to undo the setup. |

### Examples

```powershell
# Standard setup
.\scripts\tailscale-serve.ps1

# Custom port
.\scripts\tailscale-serve.ps1 -ImmichPort 8080

# Remove the HTTPS serve (revert to HTTP-only)
.\scripts\tailscale-serve.ps1 -Remove
```

---

## Troubleshooting

**"Tailscale is not installed or not in PATH"**  
Install Tailscale from https://tailscale.com/download and restart PowerShell.

**"Tailscale is not running"**  
Click the Tailscale tray icon and make sure it says "Connected."

**Certificate warning in browser**  
Wait a minute and refresh. The Let's Encrypt certificate may still be provisioning.
If the warning persists, check that **HTTPS Certificates** is enabled in the admin console (Step 2).

**Can connect at home but not away**  
Make sure Tailscale is running on the device you are connecting from, and that device is logged in to the same Tailscale account.

---

## How It Compares to Alternatives

| Method | Cost | Complexity | Security | Notes |
|---|---|---|---|---|
| **Tailscale** (this guide) | Free | Low | High | Best for personal use |
| Cloudflare Tunnel | Free | Medium | High | Good for public access; removed from this stack |
| Nginx reverse proxy | Free | High | Medium | Requires manual cert renewal |
| Router port forward | Free | Low | Low | Exposes IP publicly; not recommended |
| VPN (Wireguard) | Free | High | High | More to configure yourself |

---

## Removing Tailscale Serve

```powershell
.\scripts\tailscale-serve.ps1 -Remove
```

Or manually:
```powershell
tailscale serve --https=443 off
```

Immich will continue running on `http://localhost:2283` — only the HTTPS routing is removed.
