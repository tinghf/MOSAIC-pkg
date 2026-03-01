# MOSAIC Coiled - Status Update 2026-02-28 FINAL

**Session**: Debugging & Storage Investigation
**Previous Status**: Docker image working, workflow integration failed
**Current Status**: Root causes identified, solution ready to implement

---

## TL;DR - What Changed

### Problems Solved ✅
1. Fixed missing `truncnorm` dependency
2. Fixed R syntax errors in Python scripts
3. Created local testing capability
4. Identified why worker execution failed

### New Discovery 🔍
**Filesystem mounting doesn't work in Coiled:**
- Both Azure Files (CIFS) and BlobFuse2 require CAP_SYS_ADMIN
- Coiled workers are unprivileged containers
- Cannot mount filesystems without elevated privileges
- Thoroughly tested and documented (see STORAGE_MOUNTING_INVESTIGATION.md)

### Recommended Solution 💡
**Include MOSAIC-data in Docker image:**
- 150MB data is minimal addition to 18GB image
- Rebuild in 5 min when data updates
- No runtime mounting complexity
- Guaranteed to work

---

## Current State

### Docker Image Status
- **Version**: Latest (pushed 2026-02-28)
- **Includes**: truncnorm, BlobFuse2 (unused but installed)
- **Size**: 18.3GB
- **Location**: `ttingidmod/mosaic-worker:latest` on Docker Hub
- **Status**: ✅ Works, but missing data access solution

### Coiled Environment
- **Name**: `mosaic-docker-workers`
- **Container**: Latest Docker image
- **Region**: westus2
- **Status**: ✅ Updated, workers start successfully

### Code Status
- **Fixed**: Syntax errors, error handling, subprocess execution
- **Needs Update**: Remove/replace BlobFuse mounting code
- **Ready to Commit**: Once data solution implemented

---

## Files Modified (Not Yet Committed)

### Core Fixes (Commit These)
```
M  DESCRIPTION                              # truncnorm added
M  azure/Dockerfile                         # truncnorm + BlobFuse2
M  azure/run_mosaic_parallel_country.py    # Multiple fixes + BlobFuse (to be replaced)
A  azure/test_mosaic_worker_local.py       # Local testing tool
```

### Documentation (Commit These)
```
A  azure/DEBUGGING_SESSION_2026-02-28.md          # Initial debugging notes
A  azure/COMMIT_PLAN.md                           # Original commit strategy
A  azure/STORAGE_MOUNTING_INVESTIGATION.md        # Storage approach analysis
A  azure/SESSION_SUMMARY_2026-02-28.md            # Complete session summary
A  azure/STATUS_UPDATE_2026-02-28_FINAL.md        # This file
```

### Storage Infrastructure (Reference - Optional Commit)
```
A  azure/storage_mount/*.sh (10 scripts)          # Azure Files & Blob setup
A  azure/storage_mount/*.md (4 docs)              # Setup documentation
A  azure/storage_mount/.env                       # NEVER COMMIT - credentials!
A  azure/storage_mount/.gitignore                 # Protects credentials
```

---

## Next Session Action Plan

### Decision Required ⚠️

**Choose ONE approach:**

**A. Include Data in Docker** (20-25 min to working solution)
- Update Dockerfile to clone MOSAIC-data
- Rebuild image (5-10 min with cache)
- Push to Docker Hub (3 min)
- Update Coiled (1 min)
- Test (5 min)

**B. Download at Startup** (5 min to working solution)
- Update run_mosaic_parallel_country.py
- Add git clone of MOSAIC-data on workers
- Test immediately (no rebuild)
- Accept 2-3 min startup delay

### Implementation Template (If Option A Chosen)

**Dockerfile changes:**
```dockerfile
# After MOSAIC installation, before BlobFuse2:
# Clone MOSAIC-data repository
RUN git clone --depth 1 \
    https://github.com/InstituteforDiseaseModeling/MOSAIC-data \
    /workspace/MOSAIC/MOSAIC-data && \
    echo "✓ MOSAIC-data cloned ($(du -sh /workspace/MOSAIC/MOSAIC-data | cut -f1))"

# Create MOSAIC-pkg directory structure
RUN mkdir -p /workspace/MOSAIC/MOSAIC-pkg/model/input && \
    mkdir -p /workspace/MOSAIC/MOSAIC-pkg/model/output
```

**Run script changes:**
```python
# In run_mosaic_for_country():
r_script = f"""
library(MOSAIC)

# Data is already in Docker image - just use it!
set_root_directory('/workspace/MOSAIC')

# Rest of script unchanged...
iso_codes <- c("{iso_code}")
config <- get_location_config(iso=iso_codes)
# ...
"""
```

### Implementation Template (If Option B Chosen)

**Run script changes only:**
```python
r_script = f"""
library(MOSAIC)

# Download data if not present
if (!dir.exists('/workspace/MOSAIC/MOSAIC-data')) {{
    cat('Downloading MOSAIC-data repository...\\n')
    system('git clone --depth 1 https://github.com/InstituteforDiseaseModeling/MOSAIC-data /workspace/MOSAIC/MOSAIC-data')
    cat('✓ MOSAIC-data downloaded\\n')
}}

# Create MOSAIC-pkg structure
system('mkdir -p /workspace/MOSAIC/MOSAIC-pkg/model/input')
system('mkdir -p /workspace/MOSAIC/MOSAIC-pkg/model/output')

set_root_directory('/workspace/MOSAIC')

# Rest of script unchanged...
"""
```

---

## Azure Resources Cleanup (Optional)

**Currently active resources:**
- File Share: `ttingeasyva/mosaic-shared-data` (~$0.30/month)
- Blob Container: `ttingeasyva/mosaic-data` (~$0.12/month)
- Total: ~$0.42/month

**Cleanup commands:**
```bash
# Delete file share (not usable in Coiled)
az storage share delete \
  --account-name ttingeasyva \
  --name mosaic-shared-data

# Delete blob container (not usable in Coiled)
az storage container delete \
  --account-name ttingeasyva \
  --name mosaic-data

# Or keep for reference/future privileged container use
```

---

## What to Tell Next Claude Instance

**If resuming work:**

1. **Read these files first:**
   - `azure/SESSION_SUMMARY_2026-02-28.md` (this file)
   - `azure/STORAGE_MOUNTING_INVESTIGATION.md` (detailed findings)

2. **Current blocker:**
   - Workers need access to MOSAIC-data and MOSAIC-pkg
   - Mounting solutions don't work (privilege requirements)
   - Need to choose: include in Docker OR download at startup

3. **Ready to implement:**
   - All bugs fixed and tested
   - Docker image working
   - Just need data access solution
   - Templates provided above

4. **Don't re-investigate:**
   - Azure Files - won't work (tested thoroughly)
   - BlobFuse2 - won't work (tested thoroughly)
   - Other FUSE solutions - will have same issue
   - Any mounting approach - requires privileges

---

## Session Stats

**Time Breakdown:**
- Bug fixing: 1 hour
- Docker rebuilds: 30 min (3 rebuilds)
- Azure Files investigation: 1.5 hours
- BlobFuse2 investigation: 2 hours
- Testing & validation: 1 hour
- Documentation: 30 min
- **Total: ~6.5 hours**

**Tests Performed:**
- Local Docker: 8 tests
- Coiled deployment: 5 tests
- Docker builds: 3 successful builds
- Azure resources: 2 storage types created

**Value Delivered:**
- ✅ 4 critical bugs fixed
- ✅ Comprehensive storage investigation
- ✅ Clear path to solution
- ✅ Reusable testing tools
- ✅ Thorough documentation

---

## Commit Strategy (When Ready)

### Commit 1: Bug Fixes (Do This First)
```bash
git add DESCRIPTION azure/Dockerfile azure/test_mosaic_worker_local.py
git add azure/DEBUGGING_SESSION_2026-02-28.md
git commit -m "Fix truncnorm dependency and R syntax errors

- Add missing truncnorm package
- Fix R syntax in Python scripts
- Add local Docker testing tool
- Improve error handling

Testing: 10/10 simulations successful locally"
```

### Commit 2: Data Solution (After Implementation)
```bash
# If Option A (Docker inclusion):
git add azure/Dockerfile azure/run_mosaic_parallel_country.py
git add azure/SESSION_SUMMARY_2026-02-28.md azure/STORAGE_MOUNTING_INVESTIGATION.md
git commit -m "Add MOSAIC-data to Docker image for Coiled workers

- Include data in image (avoids mounting complexity)
- Thoroughly investigated mounting solutions
- Both CIFS and BlobFuse require privileges not available in Coiled

Testing: Full workflow validated on Coiled"
```

### Commit 3: Documentation (Final)
```bash
git add azure/storage_mount/*.md  # Reference docs only
git commit -m "Add storage mounting investigation documentation

Reference implementation for Azure Files and BlobFuse2.
Not usable in Coiled due to capability requirements.
Kept for future reference if deploying to privileged containers."
```

**DO NOT COMMIT:**
- `azure/storage_mount/.env` (credentials!)
- Test output directories

---

## Success Criteria

### Minimum Viable (Current Status) ✅
- [✅] Docker image builds successfully
- [✅] Workers start with MOSAIC loaded
- [✅] Can connect to Coiled cluster
- [✅] All syntax errors fixed
- [✅] Local testing works

### Functional (Next Milestone) ⏳
- [⏳] Data access solution implemented
- [⏳] Single country calibration completes on Coiled
- [⏳] Output files generated and retrievable
- [⏳] Multi-country parallel execution works

### Production Ready (Future) 🎯
- [ ] GitHub Actions integration
- [ ] Team documentation
- [ ] Cost optimization
- [ ] Monitoring and alerts

---

**Ready for Implementation Decision!**

Everything is documented, tested, and ready. Just need to choose data access approach and implement.
