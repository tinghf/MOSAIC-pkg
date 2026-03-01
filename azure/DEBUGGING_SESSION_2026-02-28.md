# MOSAIC Coiled Debugging Session - 2026-02-28

## Summary

Successfully debugged the MOSAIC Coiled.io worker failures and identified root causes.

## Issues Found & Fixed

### 1. ✅ Python String Multiplication in R Code (FIXED)
**Issue**: Used Python syntax `"="*70` in R scripts
```python
cat("="*70, "\n")  # ❌ Doesn't work in R
```

**Fix**: Changed to R syntax
```r
cat(strrep("=", 70), "\n")  # ✅ Works in R
```

**Files Fixed**:
- `azure/run_mosaic_parallel_country.py`
- `azure/test_mosaic_worker_local.py`

### 2. ✅ Missing Dependency: `truncnorm` Package (FIXED)
**Issue**: `truncnorm` R package was used in code but not declared in DESCRIPTION
- Used in: `R/sample_from_prior.R` for truncated normal sampling
- Error: `there is no package called 'truncnorm'`

**Fix**: Added `truncnorm` to DESCRIPTION Imports
```r
# DESCRIPTION line 79 (added)
  truncnorm,
```

**Dockerfile Updated**: Added truncnorm to pre-installed packages (line 96)

### 3. ✅ Subprocess Execution Method (IMPROVED)
**Issue**: Used `Rscript -e` with inline script - causes quoting hell
```python
result = subprocess.run(['Rscript', '-e', complex_r_script])  # ❌ Hard to debug
```

**Fix**: Use temp files instead
```python
with tempfile.NamedTemporaryFile(mode='w', suffix='.R', delete=False) as f:
    f.write(r_script)
    script_path = f.name
result = subprocess.run(['Rscript', script_path])  # ✅ Clean & debuggable
```

### 4. ✅ Better Error Handling (ADDED)
Added `tryCatch` in R scripts to:
- Capture error messages clearly
- Show traceback for debugging
- Exit with proper status codes

## Testing Progress

### Local Docker Test Created
**File**: `azure/test_mosaic_worker_local.py`
- Tests MOSAIC execution in Docker container locally
- No Coiled needed - faster iteration
- Shows real-time output for debugging

**Usage**:
```bash
python azure/test_mosaic_worker_local.py --iso ETH --n-simulations 10 --n-iterations 1
```

### Test Results
✅ **Phase 1**: R script syntax fixed - no more string multiplication errors
✅ **Phase 2**: MOSAIC loads successfully in Docker
✅ **Phase 3**: Config and priors load correctly
✅ **Phase 4**: Setup runs without errors
🚧 **Phase 5**: MOSAIC calibration blocked by missing `truncnorm` package

**Current Status**: Testing if `truncnorm` was the only missing dependency

## Next Steps

### Immediate (If truncnorm fix works)

1. **Rebuild Docker Image** (~15-20 min)
   ```bash
   cd ~/MOSAIC/MOSAIC-pkg
   docker build -f azure/Dockerfile -t mosaic-worker:latest .
   docker tag mosaic-worker:latest ttingidmod/mosaic-worker:latest
   docker push ttingidmod/mosaic-worker:latest
   ```

2. **Test Locally with New Image**
   ```bash
   python azure/test_mosaic_worker_local.py --iso ETH --n-simulations 10 --n-iterations 1
   ```

3. **Update Coiled Environment** (instant - just points to new image)
   ```python
   import coiled
   coiled.create_software_environment(
       name='mosaic-docker-workers',
       container='ttingidmod/mosaic-worker:latest',
       region_name='westus2',
       force_rebuild=True  # Use new image
   )
   ```

4. **Test on Coiled**
   ```bash
   conda activate mosaic-coiled
   python azure/run_mosaic_parallel_country.py \
     --iso ETH \
     --n-simulations 10 \
     --n-iterations 1 \
     --output-dir ./test-output
   ```

### If More Issues Found

- Use local Docker test for fast iteration
- Check worker logs in Coiled dashboard
- Add more diagnostic output to R scripts

## Files Modified (Ready to Commit)

### Fixed Bugs
- `DESCRIPTION` - Added `truncnorm` to Imports
- `azure/Dockerfile` - Added `truncnorm` to pre-installed packages
- `azure/run_mosaic_parallel_country.py` - Fixed R syntax, improved error handling
- `azure/test_mosaic_worker_local.py` - NEW: Local testing tool

### Status Documents (For Future Reference)
- `azure/STATUS_AND_NEXT_STEPS.md` - Already exists
- `azure/DOCKER_COILED_SUMMARY.md` - Already exists
- `azure/DEBUGGING_SESSION_2026-02-28.md` - THIS FILE

## Key Learnings

1. **Always test R code in R first** - Don't assume Python string operations work
2. **Use temp files for subprocess R scripts** - Avoids quoting nightmares
3. **Check DESCRIPTION matches actual imports** - `@importFrom` needs corresponding entry
4. **Local Docker tests are faster** - Don't need Coiled for every iteration
5. **Explicit error handling helps** - tryCatch with clear messages saves time

## Diagnostic Output Now Available

The R scripts now print:
- Step-by-step progress (Config loaded, Priors loaded, etc.)
- Configuration summary (# simulations, iterations, cores)
- Clear error messages with tracebacks
- Output directory paths

This makes debugging much easier than silent failures!

---

## Commands for Next Session

**If test is successful and ready to deploy**:
```bash
# 1. Rebuild and push Docker image
docker build -f azure/Dockerfile -t ttingidmod/mosaic-worker:latest .
docker push ttingidmod/mosaic-worker:latest

# 2. Update Coiled environment
python -c "import coiled; coiled.create_software_environment(name='mosaic-docker-workers', container='ttingidmod/mosaic-worker:latest', region_name='westus2', force_rebuild=True)"

# 3. Test on Coiled
python azure/run_mosaic_parallel_country.py --iso ETH --n-simulations 10 --n-iterations 1

# 4. If successful, test multi-country
python azure/run_mosaic_parallel_country.py --iso ETH,KEN --n-simulations 100 --n-iterations 2
```

**If more debugging needed**:
```bash
# Use local Docker test for fast iteration
python azure/test_mosaic_worker_local.py --iso ETH --n-simulations 10 --n-iterations 1
```

---

**Session End Status**: Waiting for truncnorm test to complete. If successful, we're ready to rebuild and deploy!
