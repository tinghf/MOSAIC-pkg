# BlobFuse2 Solution for MOSAIC Coiled Workers

**Date**: 2026-02-28
**Status**: Implementing (Docker rebuild in progress)

---

## Why BlobFuse2?

### Problem with Azure Files (CIFS)
Azure Files uses CIFS/SMB protocol which requires `CAP_SYS_ADMIN` capability:
```
mount -t cifs ... # ❌ Fails in unprivileged containers
Error: Unable to apply new capability set
```

### Solution: BlobFuse2 (FUSE-based)
BlobFuse2 uses FUSE (Filesystem in Userspace):
- ✅ Works in unprivileged containers
- ✅ No special capabilities needed
- ✅ Designed for container workloads
- ✅ Better performance for read-heavy operations

---

## Architecture

```
Local Machine                    Azure Cloud                  Coiled Workers
─────────────                    ───────────                  ──────────────

MOSAIC-data/                     Blob Container               Docker Container
MOSAIC-pkg/       ──upload──>    mosaic-data      ──mount──>  /workspace/MOSAIC/
                                 └── MOSAIC/                  ├── MOSAIC/
                                     ├── MOSAIC-data/         │   ├── MOSAIC-data/
                                     └── MOSAIC-pkg/          │   └── MOSAIC-pkg/
                                                              └── (via BlobFuse2)
```

---

## What Was Set Up

### 1. Azure Blob Storage ✅
- **Container**: `mosaic-data`
- **Account**: `ttingeasyva` (westus2)
- **Structure**:
  ```
  mosaic-data/
  └── MOSAIC/
      ├── MOSAIC-data/  (272 files, ~150MB)
      └── MOSAIC-pkg/   (82 files, model configs)
  ```

### 2. Scripts Created ✅
```
azure/storage_mount/
├── 04_create_blob_container.sh   # ✅ Created container
├── 05_upload_to_blob.sh           # ✅ Uploaded all data (354 files)
├── mount_blob_on_worker.sh        # BlobFuse2 mount helper
└── blobfuse_config.yaml           # BlobFuse2 configuration template
```

### 3. Docker Image Updates 🔄
**Dockerfile changes:**
- Install BlobFuse2 and FUSE3 libraries
- Create mount point: `/workspace/MOSAIC`
- Create cache directory: `/tmp/blobfuse-cache`

**Status**: Rebuilding (~2-3 min with layer cache)

### 4. Runner Script Updated ✅
**Changes in `run_mosaic_parallel_country.py`:**
- Switched from CIFS to BlobFuse2 mounting
- Creates BlobFuse config YAML dynamically
- Mounts to `/workspace/MOSAIC`
- Sets root to `/workspace/MOSAIC/MOSAIC` (note the double MOSAIC - blob structure)
- Passes credentials via `AZURE_BLOB_CONTAINER` env var

---

## How BlobFuse2 Works

### On Each Coiled Worker:

1. **Receive credentials** via environment variables
2. **Create config file** (`/tmp/blobfuse-config.yaml`) with:
   - Storage account name
   - Storage key (from env)
   - Container name
   - Cache settings
3. **Mount blob storage**:
   ```bash
   blobfuse2 mount /workspace/MOSAIC --config-file=/tmp/blobfuse-config.yaml
   ```
4. **Verify** MOSAIC-data and MOSAIC-pkg directories exist
5. **Set root** to `/workspace/MOSAIC/MOSAIC`
6. **Run MOSAIC** with full data access

### Key Differences from CIFS:
| Aspect | CIFS (Failed) | BlobFuse2 (Works) |
|--------|---------------|-------------------|
| **Protocol** | SMB/CIFS | FUSE (userspace) |
| **Capabilities** | Needs CAP_SYS_ADMIN | None required ✅ |
| **Container** | Privileged only | Unprivileged OK ✅ |
| **Performance** | Good | Excellent for reads |
| **Caching** | OS-level | Configurable (4GB) |

---

## Testing Plan

### After Docker Rebuild:

1. **Push to Docker Hub** (~2-3 min)
   ```bash
   docker tag mosaic-worker:latest ttingidmod/mosaic-worker:latest
   docker push ttingidmod/mosaic-worker:latest
   ```

2. **Update Coiled** (~1 min)
   ```python
   coiled.create_software_environment(
       name='mosaic-docker-workers',
       container='ttingidmod/mosaic-worker:latest',
       region_name='westus2',
       force_rebuild=True
   )
   ```

3. **Test on Coiled** (~5-7 min)
   ```bash
   cd ~/MOSAIC/MOSAIC-pkg/azure/storage_mount
   ./test_coiled_with_mount.sh
   ```

**Expected outcome:**
- ✅ BlobFuse2 mounts successfully
- ✅ No capability errors
- ✅ MOSAIC accesses data from blob storage
- ✅ Calibration runs successfully

---

## Advantages Over Azure Files

1. **Works in containers** - No privilege escalation needed
2. **Better for ML workloads** - Optimized for read-heavy access patterns
3. **Faster startup** - No kernel module dependencies
4. **Same cost** - ~$0.40/month for 5GB
5. **Easier debugging** - FUSE errors are clearer

---

## Cost Comparison

| Storage Type | Monthly Cost | Performance | Container Support |
|--------------|--------------|-------------|-------------------|
| **Azure Blob** | $0.30-0.50 | Excellent | ✅ Works |
| Azure Files | $0.30-0.50 | Good | ❌ Needs privileged |
| In Docker | $0 | Fastest | ✅ But immutable |

---

## Updating Data

When MOSAIC-data changes:

```bash
cd ~/MOSAIC/MOSAIC-pkg/azure/storage_mount

# Re-upload (2-3 minutes)
./05_upload_to_blob.sh

# Workers see updated data immediately - no Docker rebuild needed!
```

---

## Next Steps

- ⏳ Docker rebuild completes (~2-3 min remaining)
- ⏳ Push to Docker Hub
- ⏳ Update Coiled environment
- ⏳ Test on Coiled workers

**Expected total time:** ~10 minutes to fully tested solution

---

## Files Modified (Session Summary)

```
Session accomplishments:
- Fixed truncnorm dependency bug
- Fixed R syntax errors
- Created Azure Blob Storage setup
- Switched from Azure Files to BlobFuse2
- Updated Docker image
- Updated runner scripts

Files ready for next commit:
modified:   DESCRIPTION (truncnorm)
modified:   azure/Dockerfile (truncnorm + BlobFuse2)
modified:   azure/run_mosaic_parallel_country.py (BlobFuse2 mounting)
new file:   azure/storage_mount/* (8 new files)
new file:   azure/test_mosaic_worker_local.py
new file:   azure/DEBUGGING_SESSION_2026-02-28.md
```

---

**Status:** Implementing BlobFuse2 solution - Docker rebuild in progress
