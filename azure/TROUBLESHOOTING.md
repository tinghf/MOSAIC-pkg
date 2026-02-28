# MOSAIC Coiled Troubleshooting Guide

**Last Updated**: 2026-02-27

---

## Issues Found and Fixed

### ✅ Issue 1: Placeholder Config/Priors (FIXED)

**Symptom**: Runs fail immediately after cluster starts

**Root Cause**: Code was using placeholder values instead of loading actual MOSAIC configuration:
```python
config = {'iso_codes': iso_codes}  # Incomplete
priors = {'beta': {...}}  # Only 1 parameter, MOSAIC needs 30+
```

**Fix**: Now loads from R:
```python
config <- get_location_config(iso=iso_codes)
priors <- get_location_priors(iso=iso_codes)
```

**Status**: ✅ Fixed in commit 2026-02-27

---

### ✅ Issue 2: Missing Seed Parameter (FIXED)

**Symptom**: `Error: seed must be a single numeric value`

**Root Cause**: `MOSAIC::sample_parameters()` requires a `seed` argument

**Fix**: Added random seed generation:
```python
seed = np.random.randint(1, 1000000)
params <- MOSAIC::sample_parameters(..., seed = {seed})
```

**Status**: ✅ Fixed in commit 2026-02-27

---

### ✅ Issue 3: Coiled API Syntax (FIXED)

**Symptom**: `TypeError: function() got an unexpected keyword argument 'retries'`

**Root Cause**: Coiled CLI version doesn't support `--file`, `--post-build`, or `retries` parameters

**Fix**: Updated to correct syntax:
```python
# Before (incorrect)
@coiled.function(..., retries=2)
coiled env create --file azure/coiled_environment.yml --post-build ...

# After (correct)
@coiled.function(...)  # No retries parameter
coiled env create --conda azure/coiled_environment.yml
```

**Status**: ✅ Fixed in commit 2026-02-27

---

### ✅ Issue 4: AWS vs Azure VM Types (FIXED)

**Symptom**: `The instance type 'm5.2xlarge' is not supported for cloud provider 'azure'`

**Root Cause**: Code defaulted to AWS VM types, but workspace uses Azure

**Fix**: Changed to Azure VM types:
```python
# Before
WORKER_VM_TYPE = "m5.2xlarge"  # AWS
WORKER_REGION = "us-east-1"

# After
WORKER_VM_TYPE = "Standard_D8s_v6"  # Azure
WORKER_REGION = "westus2"
```

**Status**: ✅ Fixed in commit 2026-02-27

---

### ✅ Issue 5: Conda Channel Error (FIXED)

**Symptom**: `Failed to fetch package metadata from channel 'defaults'`

**Root Cause**: Coiled cannot access Anaconda `defaults` channel

**Fix**: Use only `conda-forge`:
```yaml
# Before
channels:
  - conda-forge
  - defaults  # ❌ Not accessible

# After
channels:
  - conda-forge  # ✅ Works
```

**Status**: ✅ Fixed in commit 2026-02-27

---

## 🚧 Current Blocker: Azure Quota Limits

### Issue 6: Insufficient Azure Quota (AWAITING RESOLUTION)

**Symptom**:
```
OperationNotAllowed: Exceeding approved standardDv5Family Cores quota
Current Limit: 10, Current Usage: 10, Additional Required: 2
```

**Root Cause**: Azure subscription has 10-core limit for Dv5/Dv6/Ev5/Ev6 families

**Requirements**:
- Minimum for testing: 12 cores (scheduler + 1 worker)
- Recommended for production: 100 cores (10-12 workers)

**Resolution**: Quota increase request submitted
- **Subscription**: gf-idm-nonprod-00
- **Region**: West US 2
- **Quota**: Standard Dv5 Family vCPUs
- **Current**: 10 → **Requested**: 100
- **Expected Approval**: 1-3 business days

**Workaround** (temporary):
- Use different Azure region with available quota (eastus, centralus)
- Or deallocate existing VMs to free quota

---

## Potential Future Issues

### Watch For: R Package Installation on Workers

**Risk**: Installing MOSAIC from GitHub on every worker could be slow or fail

**Mitigation**:
- Current: Workers check if MOSAIC installed, skip if present
- Timeout: 10 minutes for installation
- Keepalive: Workers persist for 5 minutes (reused across tasks)

**If Issues Occur**:
1. Increase timeout: `timeout=1200` (20 minutes)
2. Increase keepalive: `keepalive="15 minutes"`
3. Pre-bake MOSAIC into Coiled environment (use Docker image)

---

### Watch For: Dask Worker Communication Timeouts

**Risk**: Workers in westus2 may have network latency issues

**Symptoms**:
- Workers connect but tasks timeout
- Dashboard shows workers as "idle" despite pending tasks

**Mitigation**:
- Set longer task timeouts
- Check Coiled dashboard for network metrics
- Consider using Azure ExpressRoute or faster network SKUs

**If Issues Occur**:
```python
# In run_mosaic_coiled.py
cluster = coiled.Cluster(
    ...,
    scheduler_options={"idle-timeout": "15min"},
    worker_options={"death-timeout": "300s"}
)
```

---

### Watch For: R Memory Issues

**Risk**: LASER simulations may exceed worker RAM (especially with Standard_D2_v5: 8GB)

**Symptoms**:
- Workers crash mid-simulation
- OOM (Out of Memory) errors in logs

**Mitigation**:
- Use larger VMs: `Standard_D4_v5` (16GB) or `Standard_D8s_v6` (32GB)
- Reduce batch size in LASER config
- Monitor memory via Coiled dashboard

**If Issues Occur**:
```python
# In run_mosaic_coiled.py
WORKER_VM_TYPE = "Standard_E8_v5"  # Memory-optimized: 8 cores, 64GB
```

---

## Debugging Tips

### 1. Check Coiled Dashboard

Every cluster creation prints a dashboard link:
```
✅ Cluster ready: https://cloud.coiled.io/clusters/1479431
```

**Dashboard shows**:
- Worker CPU/memory usage
- Task execution times
- Network throughput
- Error logs from workers

### 2. Enable Verbose Logging

Add to `run_mosaic_coiled.py`:
```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

### 3. Test Worker Initialization

Test if workers can run basic R commands:
```python
@coiled.function(software="mosaic-pkg", vm_type="Standard_D2_v5")
def test_r():
    import subprocess
    result = subprocess.run(['Rscript', '-e', 'cat(R.version.string)'],
                           capture_output=True, text=True)
    return result.stdout

# Test
result = test_r()
print(f"R version on worker: {result}")
```

### 4. Check Coiled Environment Build Logs

```bash
coiled env logs mosaic-pkg
```

### 5. Validate MOSAIC Functions Locally

Before submitting to Coiled:
```bash
conda activate mosaic-coiled
Rscript -e "
library(MOSAIC)
config <- get_location_config(iso='ETH')
priors <- get_location_priors(iso='ETH')
params <- sample_parameters(priors=priors, n=10, seed=123)
print(head(params))
"
```

---

## Common Error Messages

| Error | Cause | Solution |
|-------|-------|----------|
| `RequestDisallowedByPolicy` | VM type blocked by Azure governance | Use allowed SKUs (Standard_D*_v5/v6) |
| `OperationNotAllowed` quota | Azure quota exceeded | Request quota increase or use different region |
| `NotSupported` encryption | VM type doesn't support encryption | Use v5/v6 families (not v4) |
| `Software environment not found` | Coiled environment not created | Run `coiled env create` |
| `seed must be numeric` | Missing seed in sample_parameters | ✅ Fixed |
| `Placeholder config` | Config not loaded from R | ✅ Fixed |

---

## Test Checklist (Post-Quota)

Before production use:

- [ ] Test cluster creation (1 worker)
- [ ] Verify MOSAIC installs on worker
- [ ] Run 10 simulations successfully
- [ ] Check results format (parquet file valid)
- [ ] Validate ESS/R² metrics match baseline
- [ ] Test with multiple workers (5-10)
- [ ] Test multi-country run (ETH+KEN)
- [ ] Monitor costs via Coiled dashboard
- [ ] Test GitHub Actions workflow
- [ ] Verify artifact upload to GitHub

---

## Support Resources

- **Coiled Docs**: https://docs.coiled.io/user_guide/troubleshooting.html
- **Coiled Support**: support@coiled.io (24-hour SLA)
- **Dask Debugging**: https://docs.dask.org/en/stable/debugging.html
- **MOSAIC Issues**: https://github.com/InstituteforDiseaseModeling/MOSAIC-pkg/issues

---

**Last Updated**: 2026-02-27
