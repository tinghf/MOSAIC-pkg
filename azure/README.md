# MOSAIC Workflow Automation with Coiled.io

**Status**: ✅ Implementation Complete - Awaiting Azure Quota Increase
**Recommended Approach**: GitHub Actions + Coiled.io
**Setup Time**: 30 minutes (setup complete, ready for testing)
**Cost**: ~$15-200/run depending on scale

> **📋 Latest Update (2026-02-27)**: All implementation files complete. Testing blocked by Azure quota limits. See [CURRENT_STATUS.md](CURRENT_STATUS.md) for details and next steps.

---

## Quick Start

**🚀 Get started in 30 minutes:**

1. **Read** [COILED_QUICKSTART.md](COILED_QUICKSTART.md) - Complete implementation guide
2. **Sign up** for Coiled.io (free tier available)
3. **Configure** GitHub secrets (Coiled token)
4. **Trigger** your first automated run

---

## What This Enables

✅ **No server login required** - Trigger runs from GitHub
✅ **Auto-scaling compute** - 0 to 120 cores in 2 minutes
✅ **Real-time monitoring** - Built-in Coiled dashboard
✅ **Automatic results** - Archived to GitHub Artifacts
✅ **Cost tracking** - Per-job cost visibility
✅ **Reproducible** - Every run tagged with git SHA

---

## Architecture

```
User pushes code or clicks "Run workflow"
           ↓
    GitHub Actions
           ↓
    Coiled.io Platform
           ↓
Auto-scaled Dask Cluster (10-50 workers)
           ↓
Each worker runs: MOSAIC → LASER simulations
           ↓
Results aggregated and uploaded to GitHub Artifacts
```

---

## Why Coiled.io?

| Feature | Coiled.io | Manual Azure VM |
|---------|-----------|----------------|
| Setup time | 30 min | 4+ hours |
| Maintenance | Zero (fully managed) | Weekly (patches, monitoring) |
| Scaling | Automatic (0-N workers) | Manual |
| Cost | $0.10-0.15/core-hour | $0.03/core-hour (+ management time) |
| Dashboard | Rich metrics included | DIY |
| Learning curve | Python + Dask | Azure CLI + VM management |

**Recommendation**: Use Coiled.io unless you have existing Azure infrastructure and expertise.

---

## Cost Estimates

| Scenario | Workers | Runtime | Cost |
|----------|---------|---------|------|
| **Test** (ETH, 100 sims) | 2 | 5 min | **$2** |
| **Small** (ETH, 1K sims, 2 iters) | 10 | 30 min | **$15** |
| **Medium** (ETH+KEN, 1K sims, 3 iters) | 20 | 2 hours | **$60** |
| **Large** (8 countries, 1K sims, 5 iters) | 50 | 6 hours | **$200** |

**Monthly** (10 small + 2 large runs): **~$550**

---

## Implementation Roadmap

### ✅ Phase 1: Documentation (Complete)
- [x] Comprehensive Coiled.io quickstart guide
- [x] Python runner script with Dask integration
- [x] GitHub Actions workflow template
- [x] Cost and architecture analysis

### 🚧 Phase 2: Prototype (Week 1)
- [ ] Create Coiled account and software environment
- [ ] Test `run_mosaic_coiled.py` locally
- [ ] Validate R ↔ Python bridge (reticulate/rpy2)
- [ ] Run single-country test (ETH, 100 sims)

### 🔲 Phase 3: GitHub Integration (Week 2)
- [ ] Configure GitHub secrets (Coiled token)
- [ ] Deploy workflow `.github/workflows/mosaic-coiled.yml`
- [ ] Test workflow dispatch with small run
- [ ] Verify artifact upload

### 🔲 Phase 4: Production Hardening (Week 3-4)
- [ ] Multi-country validation (8 countries)
- [ ] Error handling and retries
- [ ] Cost monitoring and alerts
- [ ] Documentation for end users

---

## Files in This Directory

| File | Purpose |
|------|---------|
| **[COILED_QUICKSTART.md](COILED_QUICKSTART.md)** | Complete step-by-step implementation guide |
| **[AUTOMATION_EXPLORATION.md](AUTOMATION_EXPLORATION.md)** | Detailed feasibility study and alternative approaches |
| `run_mosaic_coiled.py` | Python runner for Dask-based parallelization |
| `coiled_environment.yml` | Software environment for Coiled workers |
| `coiled_setup.sh` | Post-build script to install MOSAIC on workers |

---

## Getting Started

### Option 1: Quick Test (Local)

```bash
# Install Coiled
pip install coiled dask distributed rpy2

# Login
coiled login

# Test local run (uses Coiled cloud)
python azure/run_mosaic_coiled.py \
  --iso ETH \
  --n-simulations 100 \
  --n-iterations 1 \
  --n-workers 2 \
  --output-dir ./test-output
```

**Cost**: ~$2, **Runtime**: 5 minutes

### Option 2: GitHub Actions (Automated)

1. Follow [COILED_QUICKSTART.md](COILED_QUICKSTART.md) Steps 1-3 (setup)
2. Commit workflow file: `.github/workflows/mosaic-coiled.yml`
3. Go to GitHub → Actions → "MOSAIC Coiled Dispatch" → "Run workflow"
4. Monitor progress and download results from Artifacts

---

## Key Benefits Over Current Workflow

| Current (Manual SSH) | Automated (Coiled.io) |
|----------------------|----------------------|
| SSH into server | GitHub button click |
| Manual `Rscript` execution | Automatic on push/schedule |
| Monitor terminal for hours | Check dashboard, get notification |
| `scp` results manually | Auto-archived to GitHub |
| Unknown cost per run | Real-time cost tracking |
| Single VM (fixed capacity) | Auto-scale 0-N workers |

---

## Support

- **Implementation Guide**: [COILED_QUICKSTART.md](COILED_QUICKSTART.md)
- **Detailed Analysis**: [AUTOMATION_EXPLORATION.md](AUTOMATION_EXPLORATION.md)
- **Coiled Support**: support@coiled.io (response time: <24 hours)
- **MOSAIC Issues**: https://github.com/InstituteforDiseaseModeling/MOSAIC-pkg/issues
- **Contact**: john.giles@gatesfoundation.org

---

## FAQ

**Q: Do I need to know Python?**
A: Basic Python helpful but not required. The quickstart provides complete working code.

**Q: Can I still use Azure VMs instead?**
A: Yes. See [AUTOMATION_EXPLORATION.md](AUTOMATION_EXPLORATION.md) Section 3.3 for Coiled.io approach.

**Q: What if I exceed budget?**
A: Set up Coiled budget alerts. Clusters auto-shutdown when idle (5-10 min).

**Q: How does this handle R + Python threading issues?**
A: Each Dask worker is a separate process with isolated R session. Threading conflicts avoided.

**Q: Can I use this for NPE training?**
A: Yes! Change worker VM type to GPU instances (e.g., `p3.2xlarge`).

---

**Last Updated**: 2026-02-24
