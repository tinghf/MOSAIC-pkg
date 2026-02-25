# Azure Deployment Options for MOSAIC

This directory contains infrastructure-as-code templates for deploying MOSAIC on Azure with minimal manual setup.

## Quick Comparison

| Option | Setup Time | Best For | Cost Model | Automation Level |
|--------|-----------|----------|------------|------------------|
| **VM Image** | 5 min | Interactive development | Pay-per-hour VM | Medium |
| **Container** | 10 min | Batch jobs, CI/CD | Pay-per-second | High |
| **Batch** | 15 min | Massive parallel runs | Pay-per-task | Very High |
| **ML Compute** | 10 min | Research workflows | Pay-per-hour + storage | High |

## Current Workflow Pain Points

**Before (Manual Setup):**
```bash
# 1. Provision Azure VM manually via portal
# 2. SSH into VM
ssh user@vm-ip

# 3. Clone repo
git clone https://github.com/InstituteforDiseaseModeling/MOSAIC-pkg.git
cd MOSAIC-pkg

# 4. Run setup (20-30 minutes)
bash vm/setup_mosaic.sh

# 5. Setup data repos
cd ~/MOSAIC
git clone https://github.com/InstituteforDiseaseModeling/MOSAIC-data.git

# 6. Run RStudio and execute script
```

**Total time: 45-60 minutes before running first model**

---

## Option 1: Pre-configured VM Image ⭐ **RECOMMENDED FOR MOST USERS**

### Concept
Create a custom Azure VM image with:
- All dependencies pre-installed (R, Python, conda, system libraries)
- MOSAIC package installed
- Data repositories cloned
- RStudio Server configured

### User Workflow
```bash
# 1. Deploy from template (2 minutes)
az deployment group create \
  --resource-group mosaic-rg \
  --template-file vm-image/deploy.bicep \
  --parameters vm-image/parameters.json

# 2. Get connection info
VM_IP=$(az vm show -d -g mosaic-rg -n mosaic-vm --query publicIps -o tsv)
echo "RStudio Server: http://${VM_IP}:8787"
echo "SSH: ssh mosaicuser@${VM_IP}"

# 3. Run model immediately
ssh mosaicuser@${VM_IP}
Rscript ~/MOSAIC-pkg/vm/launch_mosaic.R
```

**Time savings: 40+ minutes per deployment**

### Pros
- Minimal learning curve (familiar VM interface)
- Interactive RStudio access for debugging
- Can pause/resume VMs to save costs
- Easy to customize after deployment

### Cons
- Manual start/stop required
- Billed per hour even if idle
- Image maintenance required for updates

### Implementation Files
- `vm-image/build-image.sh` - Creates VM image from base Ubuntu
- `vm-image/deploy.bicep` - Deploys VM from image
- `vm-image/parameters.json` - VM size, credentials, networking

---

## Option 2: Containerized Deployment (Azure Container Instances)

### Concept
Package MOSAIC as a Docker container and run on-demand using Azure Container Instances (ACI).

### User Workflow
```bash
# 1. Run model with single command (container auto-starts)
az container create \
  --resource-group mosaic-rg \
  --name mosaic-som-run \
  --image mosaicidm.azurecr.io/mosaic:latest \
  --cpu 120 --memory 456 \
  --environment-variables \
    ISO_CODE=SOM \
    N_ITERATIONS=3 \
    N_SIMULATIONS=1000 \
  --azure-file-volume-account-name mosaicstorage \
  --azure-file-volume-share-name outputs \
  --azure-file-volume-mount-path /outputs

# 2. Monitor progress
az container logs --follow -g mosaic-rg -n mosaic-som-run

# 3. Container auto-deletes when done (pay only for runtime)
```

**Time savings: Full automation, zero manual setup**

### Pros
- Zero setup time (container has everything)
- Pay-per-second billing (only while running)
- Auto-cleanup after completion
- Easy to version and share (Docker image)
- Can integrate with CI/CD pipelines

### Cons
- Requires Docker knowledge to customize
- Less interactive (command-line only)
- Container registry setup required

### Implementation Files
- `container/Dockerfile` - Container definition
- `container/build-and-push.sh` - Build and push to Azure Container Registry
- `container/run-mosaic.sh` - Wrapper script for containerized execution
- `container/aci-template.json` - ARM template for ACI deployment

---

## Option 3: Azure Batch (Massive Parallel Workflows)

### Concept
Use Azure Batch to run MOSAIC across multiple countries/regions in parallel with intelligent resource management.

### User Workflow
```bash
# 1. Submit batch job (runs 8 countries in parallel)
python3 azure/batch/submit-mosaic-batch.py \
  --countries ETH,SOM,KEN,TZA,MOZ,MWI,ZMB,ZWE \
  --pool-size 8 \
  --vm-size Standard_HB120rs_v3

# 2. Monitor via Azure portal or CLI
az batch job show --job-id mosaic-calibration-20260224

# 3. Download results when complete
az batch task file download \
  --job-id mosaic-calibration-20260224 \
  --task-id ETH \
  --file-path outputs/ETH.tar.gz \
  --destination ./outputs/
```

**Time savings: 8 countries sequentially (48+ hours) → parallel (6-8 hours)**

### Pros
- True HPC-scale parallelism (100+ simultaneous runs)
- Automatic scaling (spin up/down VMs as needed)
- Pay only for actual compute time
- Retry failed tasks automatically
- Best cost-efficiency for large batches

### Cons
- Most complex to set up initially
- Requires Azure Batch account
- 15-20 minute learning curve for batch concepts

### Implementation Files
- `batch/setup-batch-account.sh` - Initialize Batch account and pools
- `batch/submit-mosaic-batch.py` - Python script to submit jobs
- `batch/mosaic-batch-task.sh` - Task script (runs on each node)
- `batch/monitor.py` - Dashboard for job progress

---

## Option 4: Azure ML Compute (Managed ML Workflows)

### Concept
Use Azure Machine Learning managed compute instances for reproducible research workflows with experiment tracking.

### User Workflow
```bash
# 1. Submit experiment
az ml job create \
  --file azure/ml/mosaic-calibration.yml \
  --workspace-name mosaic-ml-ws \
  --resource-group mosaic-rg

# 2. Monitor via ML Studio UI
# https://ml.azure.com → Experiments → mosaic-calibration

# 3. Results auto-saved to ML workspace
```

**Time savings: Automatic experiment tracking, versioning, and artifact management**

### Pros
- Built-in experiment tracking (MLflow)
- Version control for models and data
- Jupyter notebooks for interactive analysis
- Managed compute (no VM maintenance)
- Integrates with Azure DevOps/GitHub Actions

### Cons
- Requires ML workspace setup
- Higher abstraction (less control)
- Overkill for simple runs

### Implementation Files
- `ml/setup-workspace.sh` - Create ML workspace
- `ml/mosaic-calibration.yml` - ML job specification
- `ml/environment.dockerfile` - Custom environment definition
- `ml/notebooks/` - Jupyter notebooks for analysis

---

## Cost Comparison (Example: Somalia Calibration)

**Scenario:** 3 iterations, 1000 simulations, 120 cores

| Option | VM Type | Runtime | Hourly Rate | Total Cost |
|--------|---------|---------|-------------|------------|
| Manual VM (always on) | HB120rs_v3 | 8h runtime + 16h idle | $3.00/hr | $72 |
| VM Image (stop when idle) | HB120rs_v3 | 8h runtime only | $3.00/hr | $24 |
| Container (ACI) | 120 vCPU, 456GB | 8h billed per-second | ~$2.40/hr | $19.20 |
| Batch (auto-scale) | HB120rs_v3 pool | 8h + 10% overhead | $3.00/hr | $26.40 |
| ML Compute | HB120rs_v3 | 8h + storage | $3.00/hr + $5 | $29 |

**Winner for single runs:** Container (ACI)
**Winner for parallel multi-country:** Batch
**Winner for interactive development:** VM Image

---

## Recommended Migration Path

### Phase 1: Quick Wins (Week 1)
1. **Create VM Image template** (Option 1)
   - Build image from existing `vm/setup_mosaic.sh`
   - Test deployment with `vm/launch_mosaic.R`
   - Document in MOSAIC-docs

### Phase 2: Automation (Week 2-3)
2. **Containerize MOSAIC** (Option 2)
   - Write Dockerfile based on setup script
   - Push to Azure Container Registry
   - Create ACI deployment template

### Phase 3: Scale (Month 2)
3. **Deploy Azure Batch** (Option 3)
   - Set up Batch account and pools
   - Test parallel country calibrations
   - Benchmark performance vs. single VM

### Phase 4: Research Infrastructure (Optional)
4. **Azure ML Integration** (Option 4)
   - For teams wanting experiment tracking
   - Useful for academic collaborations

---

## Next Steps

Choose your deployment option:

```bash
# Option 1: VM Image
cd azure/vm-image && bash setup.sh

# Option 2: Container
cd azure/container && bash build-and-push.sh

# Option 3: Batch
cd azure/batch && python setup-batch.py

# Option 4: ML Compute
cd azure/ml && bash setup-workspace.sh
```

See individual option READMEs for detailed instructions.
