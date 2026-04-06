# Getting Started

> **No prior technical experience needed.** Follow the steps in order and you'll have a private photo library running in about 15 minutes.

---

## What Is This?

**Immich** is a self-hosted photo and video library — think Google Photos, but running on your own computer. Your photos never leave your home unless you choose to back them up.

This setup runs Immich inside Docker, which means you don't need to install anything complicated. Docker handles everything in an isolated environment.

---

## Before You Begin

You need three things installed on your Windows PC:

| What | How to get it |
|---|---|
| **Docker Desktop** | https://www.docker.com/products/docker-desktop — download and run the installer |
| **Git** (optional, for updates) | https://git-scm.com/download/win |
| **A text editor** | Notepad works fine. VS Code is better: https://code.visualstudio.com |

After installing Docker Desktop, open it and wait until the whale icon in the taskbar says "Docker Desktop is running."

---

## Step 1 — Download This Project

If you downloaded a ZIP, extract it to a folder like `C:\immich-home`.

If you're using Git, open PowerShell and run:
```powershell
git clone https://github.com/your-repo/immich-home C:\immich-home
cd C:\immich-home
```

---

## Step 2 — Create Your Configuration File

In the project folder, find the file called `env.example`. Make a copy of it and name the copy `.env` (yes, just a dot and "env", no other name).

Open `.env` in your text editor and fill in the following:

```
UPLOAD_LOCATION=D:\immich-library
DB_DATA_LOCATION=D:\immich-db
IMMICH_VERSION=v2.6.3
TZ=America/New_York
DB_PASSWORD=some-long-random-password-here
DB_USERNAME=immich
DB_DATABASE_NAME=immich
```

> **UPLOAD_LOCATION** is where your photos will be stored. Pick a drive with plenty of space.  
> **TZ** is your timezone. Find yours at https://en.wikipedia.org/wiki/List_of_tz_database_time_zones  
> **DB_PASSWORD** can be any random string — just don't leave it as the placeholder.

If you plan to use cloud backup, also fill in the AWS section. You can skip that for now and add it later.

---

## Step 3 — Start Immich

Open PowerShell, navigate to the project folder, and run:

```powershell
cd C:\immich-home
docker compose up -d
```

Docker will download the necessary images (about 2–3 GB on first run — this takes a few minutes).

Once it's done, check that everything is healthy:

```powershell
docker compose ps
```

All services should show "healthy" or "running."

---

## Step 4 — Open Immich

Open your browser and go to:

```
http://localhost:2283
```

The first time you visit, you'll be asked to create an admin account. Use a real email and a strong password — this is your main account.

---

## Step 5 — Upload Your First Photos

You can:
- **Drag and drop** photos directly in the browser
- Use the **Immich mobile app** (iOS / Android) to automatically back up your phone

---

## Step 6 — Access from Other Devices on Your Home Network

Find your computer's local IP address:

```powershell
ipconfig
```

Look for "IPv4 Address" under your active network adapter (e.g., `192.168.1.50`).

Then visit `http://192.168.1.50:2283` from any phone, tablet, or browser on the same Wi-Fi.

---

## Step 7 — Enable Secure Remote Access (optional)

To access Immich from anywhere with a proper HTTPS address, see [https-setup.md](https-setup.md).
This uses Tailscale, which is free for personal use.

---

## Step 8 — Set Up Cloud Backup (optional but highly recommended)

Your original photos are stored on your PC. If the drive dies, they're gone.
Set up offsite backup to Amazon S3 Glacier Deep Archive for ~$0.20/month per 200 GB.

See the full setup guide: [aws-glacier-setup.md](aws-glacier-setup.md)

---

## Stopping and Starting

```powershell
# Stop everything
docker compose down

# Start again
docker compose up -d
```

Docker Desktop can also start Immich automatically when Windows boots — this is on by default.

---

## Something Went Wrong?

Check the logs:

```powershell
docker compose logs immich-server --tail 50
```

Still stuck? See the official docs at https://immich.app/docs or open an issue on this project.
