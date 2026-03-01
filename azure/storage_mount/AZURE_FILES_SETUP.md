# Azure File Share Setup - COMPLETE ✅

**Date**: 2026-02-28
**Status**: Ready for Coiled testing

## What Was Created

### 1. Azure Infrastructure ✅
- **File Share**: `mosaic-shared-data` (5GB quota)
- **Storage Account**: `ttingeasyva` (westus2)
- **Structure**:
  ```
  mosaic-shared-data/
  └── MOSAIC/
      ├── MOSAIC-data/    (150MB - all processed data)
      └── MOSAIC-pkg/     (model inputs and configs)
  ```

### 2. Setup Scripts
```
azure/storage_mount/
├── 01_create_fileshare.sh          # ✅ DONE - Created file share
├── 02_populate_fileshare.sh        # ✅ DONE - Uploaded data
├── 03_get_mount_credentials.sh    # ✅ DONE - Generated credentials
├── mount_on_worker.sh              # Helper for workers
├── test_coiled_with_mount.sh       # Quick test script
├── .env                            # Credentials (NOT COMMITTED)
├── .gitignore                      # Protects credentials
└── README.md                       # Full documentation
```

### 3. Updated Coiled Runner ✅
`azure/run_mosaic_parallel_country.py` now:
- Mounts Azure File Share on each worker
- Verifies mount succeeded before running MOSAIC
- Sets `root_directory` to `/workspace/MOSAIC` (mount point)
- Passes Azure credentials to workers via environment variables

---

## Quick Test (Ready to Run!)

```bash
cd ~/MOSAIC/MOSAIC-pkg/azure/storage_mount

# Run the test script (handles everything)
./test_coiled_with_mount.sh
```

**What this does:**
1. Loads Azure credentials from `.env`
2. Activates `mosaic-coiled` conda environment
3. Runs MOSAIC on Coiled for Ethiopia (10 sims, 1 iteration)
4. Workers mount Azure Files before executing
5. Results save to `./coiled-mount-test/`

**Expected time:** ~5-7 minutes
- Cluster creation: 1-2 min
- Mount + MOSAIC execution: 3-5 min

---

## Manual Test (If You Prefer)

```bash
# 1. Load credentials
cd ~/MOSAIC/MOSAIC-pkg
source azure/storage_mount/.env

# 2. Activate environment
conda activate mosaic-coiled

# 3. Run test
python azure/run_mosaic_parallel_country.py \
  --iso ETH \
  --n-simulations 10 \
  --n-iterations 1 \
  --output-dir ./coiled-mount-test
```

---

## How It Works

### On Each Coiled Worker:

1. **Install mount tools** (cifs-utils)
2. **Mount Azure Files** to `/workspace/MOSAIC`
3. **Verify** MOSAIC-data and MOSAIC-pkg exist
4. **Set root** directory to mount point
5. **Run MOSAIC** calibration

### Data Flow:
```
Azure Files (ttingeasyva/mosaic-shared-data)
    ↓ (CIFS mount)
Worker: /workspace/MOSAIC/
    ├── MOSAIC-data/  ← All cholera data
    └── MOSAIC-pkg/   ← Model configs
    ↓
MOSAIC: set_root_directory('/workspace/MOSAIC')
    ↓
Calibration runs with access to all data!
```

---

## Updating Data (When MOSAIC-data Changes)

```bash
cd ~/MOSAIC/MOSAIC-pkg/azure/storage_mount

# Re-upload updated data (2-3 minutes)
./02_populate_fileshare.sh

# Workers will see updated data immediately!
# No Docker rebuild, no Coiled env update needed
```

---

## Troubleshooting

### Mount fails on worker
**Symptom**: `Failed to mount Azure File Share`

**Check**:
1. Credentials are set: `echo $AZURE_STORAGE_KEY | wc -c` (should be ~88 chars)
2. File share exists: `az storage share show --name mosaic-shared-data --account-name ttingeasyva`
3. Worker has network access to Azure Files

### Permission denied
**Symptom**: `mount.cifs: permission denied`

**Fix**: Workers need root access. Coiled workers have this by default.

### Data not found after mount
**Symptom**: `Expected directory not found: /workspace/MOSAIC/MOSAIC-data`

**Check**:
```bash
# Verify upload
az storage file list \
  --account-name ttingeasyva \
  --share-name mosaic-shared-data \
  --path MOSAIC \
  --output table
```

Should show MOSAIC-data/ and MOSAIC-pkg/ directories.

---

## Cost

**Azure Files Standard (westus2):**
- Storage: 5GB × $0.06/GB/month = $0.30/month
- Transactions: ~$0.10/month (for testing)
- **Total: ~$0.40/month**

Negligible cost for development/testing!

---

## Cleanup (When Done)

```bash
# Delete file share
az storage share delete \
  --account-name ttingeasyva \
  --name mosaic-shared-data

# Remove local credentials
rm azure/storage_mount/.env
```

---

## Success Criteria

✅ **Setup Complete**: All 3 scripts ran successfully
✅ **Data Uploaded**: MOSAIC-data and MOSAIC-pkg in Azure Files
✅ **Credentials Generated**: Saved to .env (not committed)
✅ **Runner Updated**: Mounts file share before MOSAIC execution
⏳ **Coiled Test**: Ready to run with `./test_coiled_with_mount.sh`

---

**Next step:** Run `./test_coiled_with_mount.sh` to verify end-to-end!
