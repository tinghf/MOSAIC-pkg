# MOSAIC Coiled.io Automation - Status & Next Steps

**Last Updated**: 2026-02-28
**Branch**: `azure_coiled_take2_docker`
**Latest Commit**: `317e34b` - Docker + Coiled.io automation
**Session Context**: For continuation in new Claude session

---

## Quick Context Summary

**Goal**: Automate MOSAIC workflows on Coiled.io cloud infrastructure without manual server login

**Approach**: Docker container + Coiled.io (after extensive conda exploration)

**Status**: ✅ Infrastructure working, 🚧 Workflow integration in progress

---

## What's Working (100% Functional)

### Docker Image ✅
- **Image**: `ttingidmod/mosaic-worker:latest` (4.75GB)
- **Location**: Docker Hub (public)
- **Base**: rocker/geospatial:4.4
- **Contents**: MOSAIC v0.13.24, laser-cholera, pytorch, sbi, dask
- **Verified**: All dependencies check passing
- **Build command**: `docker build -f azure/Dockerfile -t mosaic-worker:latest .`
- **Test command**: `docker run --rm mosaic-worker:latest R -e "library(MOSAIC)"`

### Coiled Environment ✅
- **Name**: `mosaic-docker-workers`
- **Container**: `ttingidmod/mosaic-worker:latest`
- **Region**: westus2 (Azure)
- **Status**: Created and tested
- **Workers**: Start in <1 min with MOSAIC ready
- **Verification**: Cluster connectivity tested successfully

### Local Setup ✅
- **Conda env**: `mosaic-coiled` (existing) or `mosaic-local-orchestrate` (new)
- **Contents**: coiled, dask, pandas (minimal - no MOSAIC needed)
- **Purpose**: Run orchestration scripts locally

---

## What's In Progress (Needs Completion)

### Workflow Integration 🚧

**Two Approaches Implemented**:

1. **`run_mosaic_parallel_country.py`** (Recommended - Simple)
   - Status: Code complete, testing in progress
   - Approach: Each Coiled worker = 1 country
   - Uses: Existing `run_MOSAIC()` R function (proven code)
   - Parallelization: Country-level (ETH + KEN run simultaneously)
   - Integration: Minimal - just orchestration
   - **Issue**: Workers execute but `run_MOSAIC()` fails (need to debug why)
   - **Next**: Check worker logs to see MOSAIC error

2. **`run_mosaic_dask_bfrs.py`** (Advanced - Complex)
   - Status: Partial implementation
   - Approach: Reimpl ement BFRS in Python/Dask
   - Parallelization: Simulation-level (1000s of parallel LASER calls)
   - **Completed**: Parameter sampling, cluster setup
   - **Blocked**: LASER parameter formatting (60+ fields, complex structures)
   - **Issue**: `TypeError: 'int' object is not iterable` when calling LASER
   - **Next**: Study MOSAIC's internal parameter handling in R/run_MOSAIC.R

---

## Exact State to Resume

### Files Modified (Not Yet Committed to This Branch)
```bash
# Check current git status
cd ~/MOSAIC/MOSAIC-pkg
git status

# Files in working directory (may have uncommitted changes):
# - azure/run_mosaic_parallel_country.py (has latest fixes)
# - azure/run_mosaic_dask_bfrs.py (has parameter integration attempts)
```

### Currently Running Tests
**None** - Last test failed due to Azure quota exhaustion

**Last successful test**:
- Cluster created: ✅
- Workers connected: ✅
- MOSAIC loaded on workers: ✅
- Jobs submitted: ✅
- Execution: ❌ (both countries failed - need worker logs to see why)

### Test Commands to Resume

**Test 1: Parallel Country Execution** (Recommended to debug first)
```bash
conda activate mosaic-coiled
cd ~/MOSAIC/MOSAIC-pkg

python azure/run_mosaic_parallel_country.py \
  --iso ETH,KEN \
  --n-simulations 100 \
  --n-iterations 1 \
  --output-dir ./test-output \
  --coiled-env mosaic-docker-workers \
  --vm-type Standard_D4s_v6
```

**Test 2: Dask BFRS** (If want to pursue this approach)
```bash
python azure/run_mosaic_dask_bfrs.py \
  --iso ETH \
  --n-simulations 10 \
  --n-iterations 1 \
  --n-workers 2 \
  --output-dir ./test-output
```

---

## Known Issues & Solutions

### Issue: Azure Quota Exhausted
**Symptom**: `OperationNotAllowed: standardDv5Family Cores quota exceeded`
**Solution**:
```bash
# Delete old stopped clusters
coiled cluster list | grep stopped | head -10
# Manually delete via Coiled dashboard or wait for auto-cleanup
```

### Issue: Workers Execute but MOSAIC Fails
**Symptom**: Jobs submit successfully but return failed status
**Debug**:
1. Check Coiled dashboard: https://cloud.coiled.io/clusters/[cluster-id]
2. Click on worker
3. View stderr.txt to see actual MOSAIC error
4. Common issues:
   - Missing /workspace/data directories
   - Root directory not found
   - MOSAIC data files not accessible

**Likely fixes**:
- Mount data volumes in Docker
- Copy MOSAIC-data repo into container
- Or: Set MOSAIC to use GitHub data fetching

---

## Critical Context from Debugging

### What We Learned (Day 1: Conda Approach)

**Key Discovery**: reticulate automatically installs Miniconda on workers, which:
- Hits Anaconda ToS errors (non-interactive install blocked)
- Creates nested conda environments (fragile)
- Takes 15-30 minutes (often times out)

**Solution That Worked**: Pre-install ALL Python deps in Coiled environment
- Eliminates nested conda install
- reticulate uses existing Python
- Set `RETICULATE_PYTHON` env var

**Why We Pivoted to Docker**:
- Conda version conflicts unsolvable (r-exactextractr, GEOS/GDAL)
- Runtime installation too unreliable
- Docker pre-installation = guaranteed working environment

### What We Learned (Day 2: Docker Approach)

**Docker Build Secrets**:
- Use `rocker/geospatial` base (don't build geospatial stack from scratch!)
- Pre-install R packages that need compilation: arrow, exactextractr, hdf5r
- ggrepel needs version pinning (v0.9.5 for R 4.4)
- Install dask to conda env, not system Python (PEP 668)
- **Critical**: `ENV PATH=/root/.virtualenvs/r-mosaic/bin:$PATH` for Coiled

**Coiled Integration Secrets**:
- Coiled expects Python/dask in PATH
- Use temp files for R scripts (not `-e` - avoids quoting hell)
- `run_LASER()` signature: only takes `config`, not params/priors separately
- MOSAIC's parameter structures are complex (60+ fields)

---

## Next Steps (Priority Order)

### Immediate (Next Session)

1. **Debug Parallel Country Execution** (30-60 min)
   - Run test, check worker logs for actual error
   - Likely issue: Missing MOSAIC-data or root directory setup
   - Fix: Mount data or configure MOSAIC for cloud execution

2. **Test Single Country** (if multi-country has issues)
   - Simplify: `--iso ETH` (not ETH,KEN)
   - Isolate any data/config issues

3. **Verify Output Retrieval**
   - Ensure results save to accessible location
   - Test downloading from worker to local

### Short-term (Next Few Sessions)

1. **Complete Parallel Country Execution**
   - Get end-to-end working for 2 countries
   - Validate results match manual workflow
   - Document usage

2. **GitHub Actions Integration**
   - Create workflow to trigger Coiled runs
   - Artifact upload
   - PR comments with results

3. **Production Hardening**
   - Error handling and retries
   - Cost monitoring
   - Team documentation

### Long-term (Future)

1. **Dask BFRS Reimplementation** (Optional)
   - Only if need finer-grained parallelization
   - Requires studying MOSAIC's run_MOSAIC.R internals
   - Complex but potentially higher performance

2. **Optimization**
   - Multi-region Coiled deployments
   - Result caching
   - Parameter sweep automation

---

## Environment Pointers

### Docker Image
```bash
# Image exists locally and on Docker Hub
docker images mosaic-worker:latest
# Should show: 4.75GB image

# Pull if needed
docker pull ttingidmod/mosaic-worker:latest

# Test MOSAIC in container
docker run --rm mosaic-worker:latest R -e "library(MOSAIC); packageVersion('MOSAIC')"
```

### Coiled Environment
```bash
conda activate mosaic-coiled
coiled env list | grep mosaic-docker-workers
# Should show: mosaic-docker-workers (built)

# Recreate if needed
coiled env delete mosaic-docker-workers --yes
coiled.create_software_environment(
    name='mosaic-docker-workers',
    container='ttingidmod/mosaic-worker:latest',
    region_name='westus2'
)
```

### Local Conda Environment
```bash
# Existing: mosaic-coiled (has coiled, dask)
# Or new: mosaic-local-orchestrate

conda env list | grep mosaic
conda activate mosaic-coiled  # or mosaic-local-orchestrate
```

---

## Files to Reference

### For Understanding What Was Done
- `azure/DOCKER_COILED_SUMMARY.md` - Complete technical history
- `azure/COMMIT_README.md` - What was committed
- `azure/Dockerfile` - See how MOSAIC is installed

### For Implementation
- `azure/run_mosaic_parallel_country.py` - Recommended starting point
- `azure/run_mosaic_dask_bfrs.py` - Advanced approach (if needed)
- `vm/launch_mosaic.R` - Original manual workflow (for reference)

---

## Questions to Ask Next Claude Instance

**To get up to speed quickly**:
1. "Read azure/STATUS_AND_NEXT_STEPS.md and azure/DOCKER_COILED_SUMMARY.md"
2. "I want to continue the MOSAIC Coiled.io automation work"
3. "Let's debug why run_mosaic_parallel_country.py fails on workers"

**Key context to provide**:
- Docker image `ttingidmod/mosaic-worker:latest` is working and on Docker Hub
- Coiled environment `mosaic-docker-workers` exists and workers start successfully
- The blocker is getting `run_MOSAIC()` to execute properly on workers

---

## Critical Gotchas to Remember

1. **Azure Quota**: Only 10 cores in westus2 (often 8 in use)
   - Need to cleanup old clusters before tests
   - Or request quota increase

2. **MOSAIC Data Dependencies**:
   - MOSAIC needs access to MOSAIC-data repo or downloads from GitHub
   - Workers need `/workspace` directory structure
   - `set_root_directory()` must point to accessible location

3. **Coiled CLI Syntax**:
   - `coiled cluster list` (not `coiled cluster delete` - use dashboard or Python API)

4. **Docker PATH**:
   - Must include `/root/.virtualenvs/r-mosaic/bin` for Coiled to find Python/dask

5. **R Script Execution**:
   - Use temp files, not `Rscript -e` (avoids quoting issues)

---

## Success Criteria (When to Consider Done)

✅ **Minimum Viable** (Phase 1 - Already achieved!):
- Docker image builds
- Workers start with MOSAIC ready
- Can connect to cluster

🎯 **Functional** (Phase 2 - Next milestone):
- Run MOSAIC calibration for 1 country on Coiled
- Results save successfully
- Can retrieve results locally

🚀 **Production** (Phase 3 - Future):
- Multi-country parallel execution
- GitHub Actions integration
- Team can trigger runs via PR

---

## Useful Commands Cheat Sheet

### Docker
```bash
# Build
docker build -f azure/Dockerfile -t mosaic-worker:latest .

# Push to Docker Hub
docker tag mosaic-worker:latest ttingidmod/mosaic-worker:latest
docker push ttingidmod/mosaic-worker:latest

# Test locally
docker run --rm mosaic-worker:latest R -e "library(MOSAIC)"
```

### Coiled
```bash
# Login
conda activate mosaic-coiled
coiled login

# List environments
coiled env list

# List clusters
coiled cluster list

# Create environment (if needed)
python -c "import coiled; coiled.create_software_environment(name='mosaic-docker-workers', container='ttingidmod/mosaic-worker:latest', region_name='westus2')"
```

### Testing
```bash
# Quick test (recommended to start)
python azure/run_mosaic_parallel_country.py --iso ETH --n-simulations 10 --n-iterations 1

# Full test
python azure/run_mosaic_parallel_country.py --iso ETH,KEN --n-simulations 100 --n-iterations 2
```

---

**This file captures everything needed to continue in a new session!**

For next session, just say: "Read azure/STATUS_AND_NEXT_STEPS.md and let's continue the MOSAIC Coiled automation work"
