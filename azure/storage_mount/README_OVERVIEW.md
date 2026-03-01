# Azure Storage Mount Attempts - Overview

**Date**: 2026-02-28
**Status**: Investigation complete - Neither approach works in Coiled
**Reason**: Both require CAP_SYS_ADMIN capability

---

## What's in This Directory

This directory contains **reference implementations** of two storage mounting approaches that were thoroughly tested but ultimately cannot work in Coiled's unprivileged containers.

### Approach 1: Azure Files (CIFS/SMB)
**Files:** `01-03*.sh`, `AZURE_FILES_SETUP.md`, `mount_on_worker.sh`
- ✅ Successfully created and populated
- ❌ Cannot mount without CAP_SYS_ADMIN
- **Error**: "Unable to apply new capability set"

### Approach 2: Azure Blob + BlobFuse2 (FUSE)
**Files:** `04-05*.sh`, `BLOBFUSE_SOLUTION.md`, `mount_blob_on_worker.sh`
- ✅ Successfully created and populated
- ❌ Cannot mount without CAP_SYS_ADMIN
- **Error**: "fusermount3: mount failed: Operation not permitted"

---

## Why Keep This?

**Reference value:**
1. Documents what was tried and why it didn't work
2. Useful if deploying to privileged containers (Kubernetes, VMs)
3. Shows due diligence in exploring options
4. Saves future developers from repeating same investigation

**Azure resources created:**
- File Share: `mosaic-shared-data` (~$0.30/month)
- Blob Container: `mosaic-data` (~$0.12/month)
- Can be deleted or kept for other use cases

---

## Scripts in This Directory

### Azure Files (Scripts 01-03)
1. `01_create_fileshare.sh` - Creates Azure File Share
2. `02_populate_fileshare.sh` - Uploads MOSAIC data to File Share
3. `03_get_mount_credentials.sh` - Gets credentials and mount commands

### Azure Blob (Scripts 04-05)
4. `04_create_blob_container.sh` - Creates Blob container
5. `05_upload_to_blob.sh` - Uploads MOSAIC data to Blob Storage

### Mount Helpers (Don't work in Coiled)
- `mount_on_worker.sh` - CIFS mount script
- `mount_blob_on_worker.sh` - BlobFuse2 mount script
- `test_coiled_with_mount.sh` - Test script (fails due to privileges)

### Configuration
- `.env` - Azure credentials (NOT COMMITTED, protected by .gitignore)
- `.gitignore` - Protects sensitive files
- `blobfuse_config.yaml` - BlobFuse2 config template

---

## What Actually Works in Coiled

**See parent directory documentation:**
- `../STORAGE_MOUNTING_INVESTIGATION.md` - Full analysis
- `../SESSION_SUMMARY_2026-02-28.md` - Complete session summary
- `../STATUS_UPDATE_2026-02-28_FINAL.md` - Current status

**Recommended solution:**
Include MOSAIC-data directly in Docker image (no mounting needed)

---

## If You Want to Use These Scripts

**For VM or Kubernetes deployment** (with privileges):

```bash
# Setup
./01_create_fileshare.sh
./02_populate_fileshare.sh
source .env

# Mount (with privileges)
docker run --cap-add SYS_ADMIN ... # Then mount works
```

**For Coiled** (unprivileged):
❌ Don't use these scripts - they won't work
✅ Use Docker data inclusion instead

---

**This directory = Investigation reference, not production solution**
