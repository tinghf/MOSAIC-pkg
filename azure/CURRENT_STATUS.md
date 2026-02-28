# MOSAIC Coiled Automation - Current Status

**Date**: 2026-02-27
**Status**: ✅ Implementation Complete - Blocked by Azure Quota

---

## ✅ What's Complete

### 1. Coiled Environment Setup
- ✅ Coiled workspace configured: `ws-idm-coiled-azure` (Azure backend)
- ✅ Software environment created: `mosaic-pkg` (2.8GB)
  - Python 3.11 + R 4.3
  - Dask, distributed, numpy, pandas, pyarrow
  - Geospatial libraries (gdal, proj, geos)
- ✅ Local conda environment: `mosaic-coiled` with all dependencies

### 2. MOSAIC Installation
- ✅ MOSAIC R package v0.13.24 installed locally
- ✅ Python dependencies installed (laser-cholera, PyTorch, sbi, zuko)
- ✅ Dependencies verified - core functionality working

### 3. Implementation Files
- ✅ [run_mosaic_coiled.py](run_mosaic_coiled.py) - Python runner for Dask parallelization
- ✅ [coiled_environment.yml](coiled_environment.yml) - Software environment spec
- ✅ [.github/workflows/mosaic-coiled.yml](../.github/workflows/mosaic-coiled.yml) - GitHub Actions workflow
- ✅ [COILED_QUICKSTART.md](COILED_QUICKSTART.md) - Complete implementation guide
- ✅ [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) - Executive summary
- ✅ [AUTOMATION_EXPLORATION.md](AUTOMATION_EXPLORATION.md) - Technical feasibility study

### 4. Configuration Adjustments
- ✅ Configured for Azure backend (not AWS)
- ✅ VM type: `Standard_D2_v5` (2 cores, 8GB RAM)
- ✅ Region: `westus2`
- ✅ Fixed parameter sampling (added seed argument)
- ✅ Fixed Coiled CLI syntax for environment creation

---

## 🚧 Current Blocker: Azure Quota Limits

### Issue

Your Azure subscription has restrictive VM quotas preventing Coiled clusters from starting:

**Quota Status (westus2 region)**:
- **Dv5 Family**: 10/10 cores used (0 available)
- **Dsv6 Family**: 8/10 cores used (2 available, insufficient)

**Minimum Required for Testing**:
- Scheduler: ~2 cores
- 1 Worker: 2 cores
- **Total**: ~4 cores

**Errors Encountered**:
```
RequestDisallowedByPolicy: Your action has been blocked by AGC Policy - AGC allowed skus for vms
OperationNotAllowed: Exceeding approved standardDv5Family Cores quota (10/10 used)
```

### What's Using Current Quota

Likely candidates:
- Previous Coiled clusters (e.g., `dask-optuna-hpo-*`)
- Other Azure VMs in westus2 region

---

## 📋 Next Steps (When Ready)

### Option 1: Request Quota Increase (Recommended for Production)

**Steps**:
1. Go to Azure Portal → Quotas
2. Search for "Standard Dv5 Family"
3. Select westus2 region
4. Click "Request quota increase"
5. Request: **100 cores** (enough for 10-12 workers)
6. Justification: "MOSAIC cholera modeling - HPC workloads requiring parallel simulations"

**Timeline**: 1-3 business days for approval

**Once Approved**: Update script to use `Standard_D8s_v6` (8 cores, 32GB RAM) for better performance

---

### Option 2: Free Up Existing Quota (Quick Test)

**Check current usage**:
```bash
# List all VMs in westus2
az vm list --query "[?location=='westus2'].{name:name, size:hardwareProfile.vmSize, status:powerState}" -o table

# Stop unused VMs
az vm deallocate --name <vm-name> --resource-group <resource-group>
```

**Check/Stop Coiled clusters**:
```bash
conda activate mosaic-coiled

# List clusters
coiled cluster list

# Delete stopped clusters (frees quota)
coiled cluster delete <cluster-name>
```

**Once freed**: Re-run test with existing configuration

---

### Option 3: Try Different Region

Update `azure/run_mosaic_coiled.py`:
```python
WORKER_REGION = "eastus"  # or "centralus", "westus3"
```

Then recreate Coiled environment for new region:
```bash
coiled env create \
  --name mosaic-pkg-eastus \
  --conda azure/coiled_environment.yml \
  --region-name eastus
```

---

## 🧪 Test Command (Once Quota Available)

```bash
conda activate mosaic-coiled
cd ~/MOSAIC/MOSAIC-pkg

python azure/run_mosaic_coiled.py \
  --iso ETH \
  --n-simulations 10 \
  --n-iterations 1 \
  --n-workers 1 \
  --output-dir ./test-output
```

**Expected with current config (`Standard_D2_v5`)**:
- Spin up 1 worker (2 cores, 8GB RAM)
- Install MOSAIC on worker (~5-10 min one-time)
- Run 10 LASER simulations sequentially
- **Total time**: ~15-20 minutes
- **Cost**: ~$1-2

**Expected with production config (`Standard_D8s_v6`, 10 workers)**:
- 10 workers × 8 cores = 80 cores total
- Run 1000 simulations in parallel
- **Total time**: ~30-40 minutes
- **Cost**: ~$15-25

---

## 📊 What We Learned

### Technical Validation

Despite quota limitations, we confirmed:
1. ✅ Coiled environment builds successfully
2. ✅ MOSAIC installs and runs locally
3. ✅ Coiled cluster creation works (scheduler started)
4. ✅ Python-R bridge functional
5. ✅ All code components ready

### Azure Policy Constraints Identified

1. **AGC Policy**: Restricts certain VM SKUs
   - Blocked: Standard_E8_v5, Standard_E8_v6
   - Allowed: Standard_D*_v4/v5/v6 families

2. **Encryption Requirements**: v4 family not supported
   - Blocked: Standard_D4_v4 (no encryption at host support)
   - Allowed: v5/v6 families

3. **Quota Limits**: Very tight quotas
   - Dv5 family: 10 cores total
   - Dsv6 family: 10 cores total
   - Current usage: 10/10 cores (Dv5), 8/10 cores (Dsv6)

### Recommended Production Configuration

**After Quota Increase**:
```python
WORKER_VM_TYPE = "Standard_D8s_v6"  # 8 cores, 32GB RAM
WORKER_REGION = "westus2"
```

**For 10 workers**: 10 × 8 = 80 cores needed (request 100-core quota)

---

## 💰 Cost Estimates (Post-Quota Increase)

### Test Runs

| Scenario | Workers | VM Type | Runtime | Cost |
|----------|---------|---------|---------|------|
| **Tiny test** | 1 | D2_v5 (2 cores) | 15 min | $1 |
| **Small test** | 2 | D4_v5 (4 cores) | 10 min | $2 |
| **Medium test** | 5 | D8s_v6 (8 cores) | 30 min | $10 |

### Production Runs

| Scenario | Workers | Total Cores | Runtime | Cost |
|----------|---------|-------------|---------|------|
| **Single country** (ETH, 1K sims, 3 iters) | 10 | 80 | 45 min | $20 |
| **Multi-country** (8 countries, 1K sims, 5 iters) | 20 | 160 | 3 hours | $100 |
| **High-ESS calibration** | 30 | 240 | 6 hours | $200 |

**Monthly Budget** (10 small + 2 large): ~$400-500

---

## 📚 Documentation Deliverables

All documentation complete and ready for team review:

1. **[COILED_QUICKSTART.md](COILED_QUICKSTART.md)** - Step-by-step implementation guide
2. **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - Executive summary with cost analysis
3. **[AUTOMATION_EXPLORATION.md](AUTOMATION_EXPLORATION.md)** - Technical feasibility study
4. **[README.md](README.md)** - Quick reference
5. **[CURRENT_STATUS.md](CURRENT_STATUS.md)** - This document

---

## 🔧 For IT/Azure Admin

### Quota Increase Request Details

**Request Type**: Compute VM Cores
**Region**: West US 2 (westus2)
**VM Family**: Standard Dv5 Family
**Current Limit**: 10 cores
**Requested Limit**: 100 cores

**Justification**:
```
MOSAIC (cholera modeling) requires HPC-level parallelization for Bayesian calibration workflows.
Typical runs use 10-30 workers (Standard_D8s_v6: 8 cores, 32GB RAM each) for 80-240 cores total.
This enables epidemiological research for cholera outbreak prediction in Sub-Saharan Africa.

Use case: Automated model runs triggered from GitHub Actions, using Coiled.io for compute orchestration.
Expected usage: 10-20 runs per month, ~500 compute hours/month.
```

**Submit Request**:
- Azure Portal → Cost Management + Billing → Quotas
- Or use link from error message (auto-fills request details)

---

## ✅ What Works Right Now (Without Quota Increase)

You can still:

1. **Run MOSAIC locally** using the current manual workflow:
   ```bash
   conda activate mosaic-coiled
   Rscript vm/launch_mosaic.R
   ```

2. **Test Python-R integration** locally (without Coiled):
   ```bash
   python azure/run_mosaic_coiled.py --help
   # All parameter sampling/likelihood code works locally
   ```

3. **Prepare GitHub Actions** workflow:
   - Commit `.github/workflows/mosaic-coiled.yml`
   - Configure GitHub secret: `COILED_TOKEN`
   - Ready to trigger once quota approved

---

## 🎯 Success Criteria Checklist

### Pre-Quota Increase
- [x] Coiled account configured
- [x] Software environment created (`mosaic-pkg`)
- [x] MOSAIC installed locally
- [x] Python runner script complete
- [x] GitHub Actions workflow ready
- [x] Documentation complete

### Post-Quota Increase
- [ ] Test run completes successfully (10 sims, 1 worker)
- [ ] Results saved to `./test-output/simulations.parquet`
- [ ] Coiled dashboard accessible
- [ ] Scale to production (10+ workers, 1000+ sims)
- [ ] GitHub Actions integration tested
- [ ] Team trained on triggering workflows

---

## 📞 Contact for Quota Increase

- **Azure Subscription Owner**: [Contact IT team]
- **Coiled Support** (if quota request rejected): support@coiled.io
- **MOSAIC Team**: john.giles@gatesfoundation.org

---

## 🔄 Timeline After Quota Approval

| Phase | Duration | Tasks |
|-------|----------|-------|
| **Day 1** | 1 hour | Test with 1 worker, validate results |
| **Day 2** | 2 hours | Scale to 10 workers, run multi-country test |
| **Day 3** | 4 hours | GitHub Actions integration, team training |
| **Week 2** | Ongoing | Production use, monitoring, optimization |

---

## 💡 Alternative: Use Existing Azure VM

If quota increase takes too long, you could:

1. Use the current Hedgehog Server (Standard_HB120rs_v2, 120 cores)
2. Install `coiled` CLI on that VM
3. Run `python azure/run_mosaic_coiled.py` from the VM
4. Coiled would still manage the cluster, but you'd have guaranteed compute access

**Trade-off**: Hybrid approach - manual VM access but automated Coiled orchestration

---

**Questions?** Check [COILED_QUICKSTART.md](COILED_QUICKSTART.md) or contact support@coiled.io

**Ready to proceed when quota is available!** 🚀
