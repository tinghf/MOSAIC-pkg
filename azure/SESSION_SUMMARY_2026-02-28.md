# MOSAIC Coiled Debugging - Complete Session Summary

**Date**: 2026-02-28
**Duration**: ~6 hours
**Branch**: `azure_coiled_take2_docker`

---

## What We Accomplished

### ✅ Critical Bugs Fixed

1. **Missing Dependency**: `truncnorm` package
   - Used in `R/sample_from_prior.R` but not in DESCRIPTION
   - Added to DESCRIPTION Imports and Dockerfile
   - Validated with local Docker test (10/10 simulations successful)

2. **Syntax Errors**: Python vs R string operations
   - Fixed `"="*70` → `strrep("=", 70)` in R code
   - Fixed `strrep("=", 70)` → `"="*70` in Python code

3. **Subprocess Method**: Improved execution reliability
   - Changed from `Rscript -e` to temp file execution
   - Added comprehensive error handling with tryCatch
   - Increased error output from 1000 → 10000 chars

4. **Local Testing Tool**: Created fast iteration capability
   - `azure/test_mosaic_worker_local.py`
   - Tests identical code to Coiled workers
   - No cloud resources needed (~2-5 min vs ~10 min)

### ✅ Infrastructure Updates

**Docker Image:**
- Rebuilt with truncnorm dependency
- Added BlobFuse2 (for investigation purposes)
- Current size: 18.3GB
- Pushed to Docker Hub: `ttingidmod/mosaic-worker:latest`
- Version on Docker Hub includes all fixes

**Coiled Environment:**
- Updated to use latest Docker image
- Environment name: `mosaic-docker-workers`
- Region: westus2

### ✅ Storage Infrastructure (Exploratory)

**Azure Resources Created:**
1. File Share: `ttingeasyva/mosaic-shared-data` (354 files)
2. Blob Container: `ttingeasyva/mosaic-data` (354 files)
3. Scripts for setup, upload, mounting (10 bash scripts)

**Status**: Created but **not usable** in Coiled due to privilege requirements

---

## What We Discovered

### Critical Finding: Mounting Requires Privileges

**Both approaches tested REQUIRE CAP_SYS_ADMIN:**

1. **Azure Files (CIFS/SMB)**
   ```bash
   mount -t cifs ...
   Error: Unable to apply new capability set (exit 2)
   ```

2. **BlobFuse2 (FUSE)**
   ```bash
   blobfuse2 mount ...
   Error: fusermount3: mount failed: Operation not permitted
   ```

**Why this matters:**
- Coiled workers are unprivileged containers
- No way to grant CAP_SYS_ADMIN in Coiled
- All filesystem mounting solutions blocked
- Not a workaround - fundamental security boundary

### MOSAIC Can Partially Work Without Data

**Discovered:**
- `get_location_config()` uses built-in `config_default`
- `get_location_priors()` uses built-in `priors_default`
- Basic setup succeeds even without external data
- Actual calibration needs real data files

**Evidence from tests:**
- "Loaded Prior from priors.json" appeared even when mount failed
- Config loaded successfully without MOSAIC-data directory
- Proves built-in defaults exist and work

---

## Files Created/Modified

### Core Bug Fixes (Ready for Commit)
```
modified:   DESCRIPTION
  + Line 79: truncnorm added to Imports

modified:   azure/Dockerfile
  + Line 96: truncnorm in pre-install list
  + Lines 147-156: BlobFuse2 installation (investigatory)
  + Lines 167-171: Enhanced directory structure

modified:   azure/run_mosaic_parallel_country.py
  + Fixed R syntax errors (strrep)
  + Improved error handling (tryCatch, increased output)
  + Added temp file execution method
  + Added BlobFuse2 mounting (needs removal or replacement)
```

### New Tools (Ready for Commit)
```
new file:   azure/test_mosaic_worker_local.py
  - Local Docker testing without Coiled
  - Fast debugging iteration
  - ~400 lines of working code
```

### Storage Investigation (Reference Only - Don't Commit .env)
```
new file:   azure/storage_mount/01_create_fileshare.sh
new file:   azure/storage_mount/02_populate_fileshare.sh
new file:   azure/storage_mount/03_get_mount_credentials.sh
new file:   azure/storage_mount/04_create_blob_container.sh
new file:   azure/storage_mount/05_upload_to_blob.sh
new file:   azure/storage_mount/mount_on_worker.sh
new file:   azure/storage_mount/mount_blob_on_worker.sh
new file:   azure/storage_mount/blobfuse_config.yaml
new file:   azure/storage_mount/test_coiled_with_mount.sh
new file:   azure/storage_mount/.env (NEVER COMMIT - has credentials)
new file:   azure/storage_mount/.gitignore (protects .env)
new file:   azure/storage_mount/README.md
new file:   azure/storage_mount/SETUP_COMPLETE.md
new file:   azure/storage_mount/BLOBFUSE_SOLUTION.md
```

### Documentation (Commit These)
```
new file:   azure/DEBUGGING_SESSION_2026-02-28.md
new file:   azure/COMMIT_PLAN.md
new file:   azure/STORAGE_MOUNTING_INVESTIGATION.md
new file:   azure/SESSION_SUMMARY_2026-02-28.md (this file)
```

---

## Decisions Needed

### ⚠️ Choose Data Access Approach

**Option 1: Include in Docker** (RECOMMENDED)
```dockerfile
# Add to Dockerfile:
RUN git clone --depth 1 \
    https://github.com/InstituteforDiseaseModeling/MOSAIC-data \
    /workspace/MOSAIC/MOSAIC-data
```

**Pros**: Simple, reliable, fast startup
**Cons**: Rebuild on data updates (~5 min)
**Best for**: Stable data, deterministic results

**Option 2: Download at Startup**
```python
# Add to worker script:
system('git clone --depth 1 https://.../MOSAIC-data /workspace/MOSAIC/MOSAIC-data')
```

**Pros**: Always latest data, no rebuild
**Cons**: 2-3 min startup delay, network dependency
**Best for**: Frequently updated data

**Option 3: Hybrid**
- Include base data in Docker
- Optional git pull on startup
- Most complex but most flexible

### ⚠️ Handle Azure Resources

**Created resources still exist:**
- File share: `mosaic-shared-data` (~$0.30/month)
- Blob container: `mosaic-data` (~$0.12/month)

**Options:**
1. **Delete** - Not needed if using Docker data inclusion
2. **Keep** - Might be useful for future privileged container scenarios
3. **Keep blob, delete files** - Blob is cheaper and more useful

### ⚠️ Clean Up Code

**BlobFuse2 code in run_mosaic_parallel_country.py:**
- Currently implements BlobFuse2 mounting
- Won't work in Coiled (needs privileges)
- Should be replaced with chosen approach

**storage_mount/ directory:**
- Contains useful reference implementation
- Could keep for documentation
- Or remove if not needed

---

## Recommended Next Actions

### Immediate (Next Session)

1. **Choose data access approach** (user decision needed)

2. **If Option 1 (Include in Docker) chosen:**
   ```bash
   # Update Dockerfile
   # Rebuild (~5-10 min)
   # Push (~3 min)
   # Update Coiled (~1 min)
   # Test (~5 min)
   # Total: ~20-25 min
   ```

3. **If Option 2 (Download at startup) chosen:**
   ```bash
   # Update run_mosaic_parallel_country.py
   # Test immediately (no rebuild)
   # Total: ~5 min
   ```

4. **Validate end-to-end**:
   - Single country test
   - Multi-country test
   - Verify output files

5. **Commit changes**:
   - Core fixes (truncnorm, syntax, error handling)
   - Chosen data solution
   - Documentation
   - Test tools

### Follow-up (After Testing)

1. **Clean up Azure resources** (if not using them)
2. **Update documentation** with final solution
3. **Create usage guide** for team
4. **Plan GitHub Actions** integration

---

## Commands for Next Session

### To Resume Work

```bash
# 1. Check current state
git status
git diff azure/

# 2. Review documentation
cat azure/STORAGE_MOUNTING_INVESTIGATION.md
cat azure/SESSION_SUMMARY_2026-02-28.md

# 3. If implementing Docker data inclusion:
# Edit azure/Dockerfile - add data clone
# Then: docker build, push, update Coiled, test
```

### To Test Current State

```bash
# Local test (works already):
python azure/test_mosaic_worker_local.py --iso ETH --n-simulations 10

# Coiled test (needs data solution):
# Won't fully work until data access is resolved
```

### To Clean Up

```bash
# Delete Azure resources:
az storage share delete --account-name ttingeasyva --name mosaic-shared-data
az storage container delete --account-name ttingeasyva --name mosaic-data

# Remove credentials:
rm azure/storage_mount/.env
```

---

## Key Insights for Future Work

### Do's ✅
- Test privilege requirements locally before cloud deployment
- Use local Docker testing for fast iteration
- Read security/capability documentation carefully
- Keep solutions simple when possible

### Don'ts ❌
- Don't assume "works in containers" = "works in unprivileged containers"
- Don't debug mounting issues on expensive cloud resources
- Don't trust marketing claims - verify with tests
- Don't over-engineer when simple solutions exist

### Gotchas 🎯
- FUSE mounts need CAP_SYS_ADMIN even though they're "userspace"
- Cloud platforms restrict capabilities for security
- Built-in MOSAIC data can mask missing external data
- Error output truncation hides root causes

---

## Success Metrics

### What We Achieved ✅
- ✓ Identified root cause of worker failures (truncnorm)
- ✓ Fixed all syntax and execution errors
- ✓ Created reliable local testing tool
- ✓ Validated Docker infrastructure works
- ✓ Thoroughly investigated storage options
- ✓ Documented all findings comprehensively
- ✓ Provided clear path forward

### What Remains 🎯
- ⏳ Implement chosen data access approach
- ⏳ Validate full calibration on Coiled
- ⏳ Commit working solution
- ⏳ Clean up exploratory code/resources

---

## For Continuity

**If resuming in new session, start with:**

1. Read this file (`SESSION_SUMMARY_2026-02-28.md`)
2. Read `STORAGE_MOUNTING_INVESTIGATION.md` for detailed findings
3. Review current file modifications (`git status`)
4. Choose data access approach (Docker inclusion recommended)
5. Implement, test, commit

**Everything is documented and ready for next steps!**

---

**Session Complete** - All findings documented, decision points identified, ready for implementation.
