# Azure Deployment Decision Matrix

## Quick Reference

| Feature | VM Image | Container (ACI) | Batch | Azure ML |
|---------|----------|-----------------|-------|----------|
| **Setup Time** | 5 min | 10 min | 15 min | 15 min |
| **Learning Curve** | Low | Medium | Medium | High |
| **Interactive Access** | ✅ Yes (RStudio) | ❌ No | ❌ No | ✅ Yes (Jupyter) |
| **Auto-scaling** | ❌ Manual | ❌ Fixed | ✅ Yes | ✅ Yes |
| **Pay-per-second** | ❌ Per-hour | ✅ Yes | ✅ Yes | ❌ Per-hour |
| **Parallel Countries** | Manual | 1 at a time | Unlimited | Moderate |
| **Auto-cleanup** | ❌ Manual | ✅ Yes | ✅ Yes | ✅ Yes |
| **Best for...** | Development | Single runs | Bulk production | Research |
| **Hourly Cost (120 cores)** | $3.00 | ~$2.40 | $3.00 (auto-scale) | $3.00 + storage |
| **Min Monthly Commitment** | None | None | None | None |

## Detailed Comparison

### Option 1: VM Image ⭐

**Strengths:**
- ✅ Fastest to get started (5 min from image)
- ✅ Familiar VM interface (SSH, RStudio)
- ✅ Interactive debugging with RStudio Server
- ✅ Easy to customize and experiment
- ✅ Can pause/resume work sessions
- ✅ Full control over environment

**Weaknesses:**
- ❌ Manual start/stop required (costs add up if forgotten)
- ❌ Per-hour billing (even if idle)
- ❌ Limited parallelism (one country at a time)
- ❌ Image maintenance needed for updates

**Cost Profile:**
- $3.00/hour when running
- $0/hour when deallocated
- **Risk:** Forgetting to stop = $2,160/month waste

**Ideal User Profiles:**
1. **Researchers** developing new MOSAIC features
2. **Students** learning cholera modeling
3. **Analysts** running occasional calibrations with manual tweaking
4. **Developers** debugging complex parameter issues

**Real-World Example:**
```
Scenario: PhD student calibrating Ethiopia, needs to experiment with priors

Timeline:
- Day 1: Deploy VM (5 min), run initial calibration (8 hours)
- Day 2: Analyze results in RStudio (2 hours), tweak parameters
- Day 3: Re-run with adjusted priors (8 hours)
- Day 4: Final analysis and visualization (3 hours)

Total runtime: 21 hours over 4 days
Total cost: $63 (21 × $3.00)

With auto-shutdown: ~$30 (10 active hours)
```

---

### Option 2: Container (ACI) ⭐⭐

**Strengths:**
- ✅ Zero manual cleanup (auto-deletes when done)
- ✅ Pay-per-second billing (most cost-efficient)
- ✅ Reproducible environments (Docker)
- ✅ Easy to version and share
- ✅ Integrates with CI/CD pipelines
- ✅ No "forgot to stop VM" risk

**Weaknesses:**
- ❌ No interactive access (command-line only)
- ❌ Harder to debug (must rebuild container to change code)
- ❌ Single country per container (manual parallelism)
- ❌ Requires Docker knowledge

**Cost Profile:**
- ~$2.40/hour (pay-per-second)
- Automatically stops and deletes when complete
- **Zero risk** of forgetting to stop

**Ideal User Profiles:**
1. **Production teams** running scheduled calibrations
2. **DevOps engineers** building automated workflows
3. **Cloud-native developers** comfortable with containers
4. **Cost-conscious teams** needing guaranteed cleanup

**Real-World Example:**
```
Scenario: Weekly automated calibration for 3 countries

Setup:
- Build container once (15 min)
- Push to Azure Container Registry

Weekly runs:
- Monday 2 AM: Deploy SOM container (auto-run, auto-delete)
- Monday 2 AM: Deploy ETH container (parallel)
- Monday 2 AM: Deploy KEN container (parallel)

Each run:
- 8 hours runtime
- $19.20 cost per country
- Total: $57.60/week for 3 countries

Monthly cost: ~$230 (fully automated, zero maintenance)
```

---

### Option 3: Azure Batch ⭐⭐⭐

**Strengths:**
- ✅ True HPC-scale parallelism (100+ simultaneous tasks)
- ✅ Auto-scaling pools (spin up/down as needed)
- ✅ Best cost-efficiency for bulk runs
- ✅ Built-in retry logic for failed tasks
- ✅ Task dependency management
- ✅ Most efficient for multi-country studies

**Weaknesses:**
- ❌ Steeper learning curve (Batch concepts)
- ❌ Requires Batch account setup
- ❌ More complex monitoring
- ❌ Overkill for single runs

**Cost Profile:**
- Same per-hour rate as VMs ($3.00/hr)
- Auto-scales: 0 nodes when idle = $0
- Pay only for active tasks
- **Massive time savings** from parallelism

**Ideal User Profiles:**
1. **Research teams** calibrating 10+ countries
2. **Production pipelines** running nightly batch jobs
3. **Large-scale studies** (all Sub-Saharan Africa)
4. **Cost-sensitive orgs** needing max efficiency

**Real-World Example:**
```
Scenario: Calibrate all 25 Sub-Saharan African countries

Without Batch (sequential on single VM):
- 25 countries × 8 hours each = 200 hours
- Cost: 200 × $3.00 = $600
- Timeline: 8+ days

With Batch (25 parallel tasks):
- 25 countries × 8 hours (parallel) = 8 hours total
- Cost: 25 × 8 × $3.00 = $600 (same cost)
- Timeline: 8 hours (96% faster!)

With Batch (auto-scaling, 10 parallel):
- Pool auto-scales 0 → 10 nodes → 0
- 25 countries in 3 batches: 8h + 8h + 8h = 24 hours
- Cost: ~$720 (includes scaling overhead)
- Timeline: 1 day instead of 8 days

Time saved: 7 days
```

---

### Option 4: Azure ML Compute 🔬

**Strengths:**
- ✅ Built-in experiment tracking (MLflow)
- ✅ Version control for data, models, results
- ✅ Jupyter notebooks for analysis
- ✅ Managed infrastructure (no maintenance)
- ✅ Integrates with Azure DevOps
- ✅ Best for reproducible research

**Weaknesses:**
- ❌ Most complex setup
- ❌ Higher abstraction (less control)
- ❌ Additional costs (storage, logging)
- ❌ Overkill for simple calibrations

**Cost Profile:**
- Compute: $3.00/hour (same as VM)
- Storage: ~$5-20/month (model artifacts)
- Logging: ~$1-5/month (experiment tracking)

**Ideal User Profiles:**
1. **Academic labs** publishing papers (reproducibility)
2. **Multi-team orgs** sharing models/results
3. **Grant-funded research** (audit trail required)
4. **ML teams** already using Azure ML

**Real-World Example:**
```
Scenario: Multi-year cholera forecasting project with 5 researchers

Setup:
- Create ML workspace (one-time, 15 min)
- Define compute targets

Benefits:
- All calibrations logged automatically
- Parameters, metrics tracked for every run
- Easy to compare: "Which Ethiopia run had best R²?"
- Notebooks for analysis shared via workspace
- Publications cite exact experiment IDs

Monthly cost:
- Compute: ~$200 (intermittent runs)
- Storage: $10 (TBs of model artifacts)
- Logging: $5
Total: ~$215/month

Value: Reproducibility worth the 10% overhead
```

---

## Decision Flowchart

```
START: I need to run MOSAIC on Azure
│
├─ Q1: Is this for learning/development?
│   YES → **VM Image** (Option 1)
│         - Get RStudio access
│         - Experiment interactively
│         - Remember to stop when done!
│
├─ Q2: Is this a one-off automated run?
│   YES → **Container** (Option 2)
│         - Zero maintenance
│         - Guaranteed cleanup
│         - Best cost per run
│
├─ Q3: Do I need to run 5+ countries?
│   YES → **Batch** (Option 3)
│         - Massive parallelism
│         - Auto-scaling
│         - Best time-to-results
│
└─ Q4: Do I need experiment tracking?
    YES → **Azure ML** (Option 4)
          - Reproducible research
          - Multi-team collaboration
          - Version control for models
```

## Cost Optimization Strategies

### Strategy 1: Hybrid Approach (Development → Production)

**Phase 1: Development** (VM Image)
- Use VM with auto-shutdown for interactive work
- Develop and test parameter configurations
- Estimated: 20 hours over 2 weeks = $60

**Phase 2: Production** (Container or Batch)
- Deploy finalized configuration to containers
- Run batch calibrations automatically
- Estimated: 50 runs × 8 hours × $2.40 = $960

**Total: $1,020 for full study**

### Strategy 2: Spot Instances (70% Savings)

Azure Batch and ACI support **Spot VMs** at 70-90% discount:

```bash
# Batch with Spot VMs
az batch pool create \
  --pool-id mosaic-spot \
  --vm-size Standard_HB120rs_v3 \
  --target-low-priority-nodes 10  # Spot instances
```

**Trade-off:** Can be preempted (interrupted) by Azure

**Best for:**
- Non-urgent bulk runs
- Calibrations that can resume if interrupted
- Cost-sensitive projects

**Example:**
- Regular: 100 hours × $3.00 = $300
- Spot: 100 hours × $0.60 = $60 (80% savings!)

### Strategy 3: Scheduled Scaling

**Use Case:** Run calibrations every Monday at 2 AM

**Setup:**
1. Create Azure Automation account
2. Schedule VM start at 1:45 AM
3. Run MOSAIC container at 2:00 AM
4. Schedule VM stop at 11:00 AM

**Cost:**
- 9 hours/week × $3.00 = $27/week
- Monthly: ~$110 (vs $2,160 if always on)

---

## Migration Path

### Phase 1: Proof of Concept (Week 1)

**Goal:** Test MOSAIC on Azure, validate costs

**Action:**
```bash
# Deploy VM Image
cd azure/vm-image
bash build-image.sh
```

**Test run:** Single country calibration
**Expected cost:** < $50

### Phase 2: Automation (Week 2-3)

**Goal:** Eliminate manual intervention

**Action:**
```bash
# Build container
cd azure/container
bash build-and-push.sh
bash deploy-aci.sh SOM
```

**Test run:** Automated calibration with cleanup
**Expected cost:** < $100

### Phase 3: Scale (Month 2)

**Goal:** Run all 25 countries efficiently

**Action:**
```bash
# Setup Batch
cd azure/batch
bash setup-batch-account.sh
python submit-mosaic-batch.py --countries ETH,SOM,KEN,...
```

**Production run:** Full Sub-Saharan Africa
**Expected cost:** $500-800 (vs weeks on local machines)

---

## Common Mistakes to Avoid

### ❌ Mistake 1: Leaving VMs running

**Problem:** Forgot to stop VM, billed 720 hours/month = $2,160

**Solution:**
- Use Bicep template with auto-shutdown
- Set Azure cost alerts at $100
- Use Container option instead (auto-cleanup)

### ❌ Mistake 2: Using VM for production batch jobs

**Problem:** Manually SSHing and running 25 countries sequentially = 200 hours

**Solution:**
- Use Batch for parallel execution = 8-24 hours
- Time saved: 7+ days

### ❌ Mistake 3: Over-provisioning resources

**Problem:** Using 120-core VM for 1000-simulation runs that only need 32 cores

**Solution:**
- Start with Standard_D32s_v3 ($1.54/hr)
- Scale up only if needed
- Savings: 50% on compute

### ❌ Mistake 4: Not using Spot instances for non-urgent runs

**Problem:** Paying full price for batch jobs that don't need to finish immediately

**Solution:**
- Use `--target-low-priority-nodes` in Batch
- Savings: 70-90% on compute

---

## Support and Resources

**Azure Pricing Calculator:**
https://azure.microsoft.com/pricing/calculator/

**MOSAIC Documentation:**
https://institutefordiseasemodeling.github.io/MOSAIC-docs/

**Azure Batch Documentation:**
https://docs.microsoft.com/azure/batch/

**Cost Management:**
https://portal.azure.com/#view/Microsoft_Azure_CostManagement/

**Issues and Questions:**
https://github.com/InstituteforDiseaseModeling/MOSAIC-pkg/issues
