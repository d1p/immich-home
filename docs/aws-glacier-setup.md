# AWS S3 Glacier Deep Archive — Setup Guide

This guide walks through setting up Amazon S3 Glacier Deep Archive for Immich offsite backups.
It assumes no prior AWS experience.

**Cost estimate**: ~$0.20/month for a 200 GB photo library.

---

## Why Glacier Deep Archive and Not Standard S3?

The short answer: this backup is **write-once, read-never-in-normal-use**.
You upload daily but you only download if your drive dies — maybe once in 5 years.
Glacier Deep Archive is priced exactly for that pattern.

### Storage cost comparison (200 GB)

| Tier | Storage/month | Retrieval model | Best for |
|---|---|---|---|
| **S3 Standard** | ~$4.60 | Instant (milliseconds) | Files you read constantly |
| S3 Intelligent-Tiering | ~$2.30–$4.60 | Instant | Unpredictable access patterns |
| Glacier Instant Retrieval | ~$0.80 | Instant (milliseconds) | Backups you might restore urgently |
| Glacier Flexible Retrieval | ~$0.72 | 3–12 hours | Infrequent restores, some urgency |
| **Glacier Deep Archive** | **~$0.20** | **12–48 hours** | **Disaster recovery only** |

Glacier Deep Archive is **23× cheaper** than S3 Standard for the same data.

### What about restore cost?

A common concern is that Glacier charges a retrieval fee that Standard S3 does not.
In practice, this barely matters for a full-library restore:

| Cost component | S3 Standard | Glacier Deep Archive |
|---|---|---|
| Data transfer out (200 GB) | ~$18.00 | ~$18.00 |
| Retrieval fee (200 GB) | $0.00 | ~$0.50 |
| **Total one-time restore** | **~$18.00** | **~$18.50** |

The data transfer charge dominates, and it is **identical on both tiers**.
The real Glacier penalty is only $0.50 per full restore.

### Annual total cost of ownership

| Tier | Storage/year | Restore (once in 5 yrs, amortised) | **Total/year** |
|---|---|---|---|
| S3 Standard | $55.20 | $3.60 | **~$58.80** |
| Glacier Deep Archive | $2.40 | $3.70 | **~$6.10** |

**Savings: ~$52/year at 200 GB.** The gap grows linearly with library size.

### When you would choose a different tier

- Pick **Glacier Instant Retrieval** if a 12–48 hour wait is genuinely unacceptable (most home users it is not).
- Pick **S3 Standard** only if you want to use the same bucket to serve files to users or access them frequently.
- For a home photo backup that you hope to never restore, Deep Archive is the right call.

---

## What You Are Setting Up

```
Your PC (Immich)
      │
      │  daily at 03:00
      ▼
Amazon S3 Bucket  ─── storage class: Glacier Deep Archive
      │
      │  disaster recovery (12-48h thaw, then download)
      ▼
Restored files on your PC
```

You will create:
- An **AWS account** (if you don't have one)
- An **S3 bucket** — the "folder" in the cloud where backups are stored
- An **IAM user** — a limited-access account just for this backup, with no other AWS permissions
- **Access keys** — the credentials rclone uses to write to the bucket

---

## Part 1: Create an AWS Account

> Skip this part if you already have an AWS account.

1. Go to https://aws.amazon.com and click **Create an AWS Account**.
2. Enter your email address and choose an account name (e.g. `home-server`).
3. Set a strong root password. Store it in a password manager — you will rarely use it.
4. Choose **Personal** account type and fill in the details.
5. Enter a credit card. You will not be charged unless you exceed free tier or use paid services.
6. Complete phone verification.
7. Choose the **Basic support** plan (free).
8. Sign in to the [AWS Console](https://console.aws.amazon.com).

> **Security tip**: After signing in, go to your account name (top right) → **Security credentials**
> and enable **Multi-Factor Authentication (MFA)** on the root account. Use an authenticator app.
> You should never use the root account for day-to-day operations — that is what the IAM user below is for.

---

## Part 2: Create the S3 Bucket

The bucket is where your backups will live.

1. In the AWS Console search bar, type **S3** and open it.

2. Click **Create bucket**.

3. Fill in the settings:

   | Field | Value |
   |---|---|
   | **Bucket name** | Something unique, e.g. `yourname-immich-backup-2026` |
   | **AWS Region** | Pick the region closest to you (e.g. `eu-central-1` for Europe, `ap-southeast-1` for Southeast Asia) |
   | **Object Ownership** | ACLs disabled (recommended) |
   | **Block all public access** | ✅ Leave all 4 boxes **checked** — this bucket must never be public |
   | **Bucket Versioning** | Enable |
   | **Default encryption** | Server-side encryption with Amazon S3 managed keys (SSE-S3) — it is the default, leave it |

4. Click **Create bucket**.

### Set Glacier Deep Archive as the default storage class

This ensures every file uploaded automatically goes to Glacier without extra configuration.

1. Open your new bucket and go to the **Management** tab.
2. Click **Create lifecycle rule**.
3. Fill in:

   | Field | Value |
   |---|---|
   | **Rule name** | `glacier-transition` |
   | **Rule scope** | Apply to all objects |

4. Under **Lifecycle rule actions**, check **Transition current versions of objects between storage classes**.
5. Set:
   - Storage class: **Glacier Deep Archive**
   - Days after object creation: **0** (transition immediately)

6. Also check **Delete expired object delete markers or incomplete multipart uploads** and set:
   - Delete incomplete multipart uploads after **7 days**

7. Click **Create rule**.

> You will see a warning that transitioning at day 0 incurs a minimum 180-day storage charge per object.
> This is normal for Glacier Deep Archive and is already factored into the ~$1/TB/month estimate.

---

## Part 3: Create an IAM User

You will create a dedicated IAM user that only has permission to read/write this specific bucket.
This way, if the credentials are ever leaked, the damage is limited.

### 3a. Create the permission policy

1. In the AWS Console search bar, type **IAM** and open it.
2. In the left sidebar, click **Policies** → **Create policy**.
3. Click the **JSON** tab and paste the following, replacing `YOUR-BUCKET-NAME` with your actual bucket name:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucket",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME"
    },
    {
      "Sid": "ReadWriteObjects",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:RestoreObject",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload"
      ],
      "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME/*"
    }
  ]
}
```

4. Click **Next**, give the policy a name: `immich-glacier-backup`
5. Click **Create policy**.

### 3b. Create the IAM user

1. In the IAM left sidebar, click **Users** → **Create user**.
2. Set:
   - **User name**: `immich-backup`
   - Do **not** check "Provide user access to the AWS Management Console"
3. Click **Next**.
4. Choose **Attach policies directly**.
5. Search for `immich-glacier-backup` and check it.
6. Click **Next** → **Create user**.

### 3c. Generate access keys

1. Click on the `immich-backup` user you just created.
2. Go to the **Security credentials** tab.
3. Scroll to **Access keys** → click **Create access key**.
4. Choose **Other** as the use case → click **Next**.
5. Click **Create access key**.
6. You will see two values:
   - **Access key ID** — starts with `AKIA...`
   - **Secret access key** — shown only once, copy it now

> **Important**: Copy both values now. The secret access key cannot be retrieved again.
> Store them in a password manager.

---

## Part 4: Configure Immich

Edit the `.env` file in this project and fill in the four AWS variables:

```env
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
S3_BUCKET_NAME=yourname-immich-backup-2026
S3_REGION=eu-central-1
```

Use the region code for the region you selected in Part 2:

| Region | Code |
|---|---|
| US East (N. Virginia) | `us-east-1` |
| US West (Oregon) | `us-west-2` |
| EU (Frankfurt) | `eu-central-1` |
| EU (Ireland) | `eu-west-1` |
| Asia Pacific (Singapore) | `ap-southeast-1` |
| Asia Pacific (Mumbai) | `ap-south-1` |
| Asia Pacific (Tokyo) | `ap-northeast-1` |

---

## Part 5: Test the Backup

Run a manual backup to confirm the connection works before relying on the daily schedule:

```powershell
# From the immich-home project directory:
docker compose run --rm backup-glacier
```

You should see output like:

```
Glacier sync started: Mon Apr  6 03:00:00 UTC 2026
Destination: s3-glacier:yourname-immich-backup-2026/immich
Syncing upload/ ...
...
Glacier sync completed: Mon Apr  6 03:05:00 UTC 2026
```

### Verify files appeared in S3

1. Go to the AWS Console → S3 → your bucket.
2. Open the `immich/` folder.
3. You should see `upload/`, `backups/`, etc. with a **Storage class** of `DEEP_ARCHIVE`.

If the storage class shows `STANDARD` instead of `DEEP_ARCHIVE`, wait 24 hours — the lifecycle rule
transitions objects after creation.

---

## Part 6: Understand the Costs

### Storage
Glacier Deep Archive costs **$0.00099 per GB per month** (~$1/TB/month).

| Library size | Monthly cost |
|---|---|
| 50 GB | ~$0.05 |
| 200 GB | ~$0.20 |
| 1 TB | ~$1.00 |
| 6 TB | ~$6.00 |

### Requests
Uploading is very cheap. A full initial backup of 200 GB might cost ~$0.10 in PUT requests.
The daily incremental syncs (only new/changed files) cost fractions of a cent.

### Retrieval (disaster recovery only)
You only pay for retrieval when you actually need to restore. Using the Bulk tier (12-48 hours):
- ~$0.0025 per GB retrieved
- 200 GB restore ≈ **$0.50** in retrieval fees
- Plus AWS data transfer out: ~$0.09/GB → **$18.00** for 200 GB

**Total one-time restore cost for 200 GB: ~$18.50**

> Note: the $18 data transfer fee applies equally to S3 Standard. The difference between
> Glacier Deep Archive and Standard for a one-time restore is only $0.50 — but Standard
> costs ~$55/year in storage vs ~$2.40/year for Glacier Deep Archive. Deep Archive saves
> ~$52/year for a $0.50 retrieval penalty.

### Minimum storage duration
Glacier Deep Archive has a **180-day minimum** storage duration per object. If you delete a file
within 180 days of uploading it, you are still charged for 180 days. This is usually not a concern
for a photo backup that rarely deletes objects.

### Setting a spend alert (recommended)

To avoid surprise bills:

1. AWS Console → search **Billing** → **Budgets** → **Create budget**.
2. Choose **Cost budget** → use the template **Zero spend budget** (alerts if you spend anything above the free tier).
3. Or set a **Fixed budget** of $5/month and get an email at 80% ($4) and 100% ($5).

---

## Troubleshooting

### "NoCredentialProviders: no valid providers in chain"
The `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` in `.env` is wrong or empty.
Double-check the values and restart: `docker compose up -d backup-glacier`.

### "AccessDenied" error
The IAM user does not have permission to access the bucket.
Go to IAM → Users → `immich-backup` → Permissions and verify the `immich-glacier-backup` policy is attached.
Also check the bucket name in the policy matches exactly (case-sensitive).

### "NoSuchBucket" error
The `S3_BUCKET_NAME` in `.env` does not match the bucket you created, or the `S3_REGION` is wrong.
S3 bucket names are global but region-specific for access.

### Files are showing as STANDARD not DEEP_ARCHIVE
The lifecycle rule transitions objects after creation. Check the Management tab of your bucket
and verify the `glacier-transition` lifecycle rule is enabled. Wait up to 24 hours after the rule
was created for it to take effect on existing objects.

### Restore script: "object is not in Glacier / cannot restore"
Objects must first be uploaded and transitioned to DEEP_ARCHIVE before they can be restored.
Check the storage class in the S3 console. If the bucket was created recently, allow 24 hours
for the lifecycle transition to complete.
