# Azure Deployment Quick Start Guide

Choose your deployment path based on your needs:

## 🚀 **Quick Decision Tree**

```
Do you need to run MOSAIC on Azure?
│
├─ YES → Do you need to run 5+ countries in parallel?
│   │
│   ├─ YES → **Use Azure Batch** (Option 3)
│   │         Best for: Massive parallel calibrations
│   │         Setup time: 15 minutes
│   │         Cost: Most efficient for bulk runs
│   │
│   └─ NO → Do you need interactive development (RStudio)?
│       │
│       ├─ YES → **Use VM Image** (Option 1)
│       │         Best for: Interactive work, debugging
│       │         Setup time: 5 minutes
│       │         Cost: $3/hour (stop when not in use)
│       │
│       └─ NO → **Use Container** (Option 2)
│                 Best for: Automated runs, CI/CD
│                 Setup time: 10 minutes
│                 Cost: Pay per second
│
└─ NO → Use local setup or existing VM
```

---

## Option 1: VM Image (Fastest Start)

**Use this if:** You want to get started immediately with minimal setup.

### Step 1: Build the image (one-time setup)

```bash
cd azure/vm-image
bash build-image.sh
```

This takes ~30 minutes but only needs to be done once.

### Step 2: Deploy a VM

```bash
# Edit parameters.json with your SSH key
nano parameters.json

# Deploy VM
az deployment group create \
  --resource-group mosaic-rg \
  --template-file deploy.bicep \
  --parameters @parameters.json

# Get IP address
VM_IP=$(az vm show -d -g mosaic-rg -n mosaic-vm --query publicIps -o tsv)
```

### Step 3: Run MOSAIC

```bash
# SSH into VM
ssh mosaicuser@$VM_IP

# Run calibration
cd ~/MOSAIC/MOSAIC-pkg
Rscript vm/launch_mosaic.R
```

**Or use RStudio:**
- Open browser: `http://$VM_IP:8787`
- Login: `mosaicuser` / `mosaic2024`
- Open: `~/MOSAIC/MOSAIC-pkg/vm/launch_mosaic.R`

### Step 4: Stop VM when done (save money)

```bash
az vm deallocate -g mosaic-rg -n mosaic-vm
```

**Cost:** ~$3/hour when running, $0 when stopped

---

## Option 2: Container (Best Automation)

**Use this if:** You want automated, reproducible runs without managing VMs.

### Step 1: Build and push container (one-time setup)

```bash
# Create container registry
az acr create \
  --name mosaicidm \
  --resource-group mosaic-rg \
  --sku Basic

# Build and push
cd azure/container
bash build-and-push.sh
```

### Step 2: Run MOSAIC

```bash
# Single command to run calibration
bash deploy-aci.sh SOM  # Run Somalia calibration

# Or manually specify resources
az container create \
  --resource-group mosaic-rg \
  --name mosaic-som \
  --image mosaicidm.azurecr.io/mosaic:latest \
  --cpu 120 --memory 456 \
  --environment-variables ISO_CODE=SOM N_SIMULATIONS=1000
```

### Step 3: Monitor progress

```bash
# Follow logs
az container logs --follow -g mosaic-rg -n mosaic-som

# Check status
az container show -g mosaic-rg -n mosaic-som --query instanceView.state
```

### Step 4: Download results

```bash
# Container auto-creates tar.gz archive
# If using Azure Files, download with:
az storage file download-batch \
  --account-name mosaicstorage \
  --source outputs \
  --destination ./outputs/
```

**Cost:** ~$2.40/hour, billed per second (only while running)

---

## Option 3: Batch (Massive Parallelism)

**Use this if:** You need to run 5+ countries simultaneously.

### Step 1: Setup batch account (one-time)

```bash
cd azure/batch
bash setup-batch-account.sh
```

### Step 2: Submit batch job

```bash
# Install Python dependencies
pip install azure-batch azure-storage-blob

# Run 8 countries in parallel
python submit-mosaic-batch.py \
  --countries ETH,SOM,KEN,TZA,MOZ,MWI,ZMB,ZWE \
  --pool-size 8
```

### Step 3: Monitor job

```bash
# Watch progress
python monitor-batch.py --job-id mosaic-20260224-120000 --follow

# Or use Azure CLI
az batch task list --job-id mosaic-20260224-120000 --output table
```

### Step 4: Download results

```bash
# Download logs for specific task
python monitor-batch.py --download-logs mosaic-20260224-120000:task-ETH

# Or use Azure CLI
az batch task file download \
  --job-id mosaic-20260224-120000 \
  --task-id task-ETH \
  --file-path stdout.txt
```

**Cost:** Same per-hour rate as VMs, but auto-scales (only pay for active tasks)

---

## Cost Comparison Example

**Scenario:** Run calibrations for 8 countries (ETH, SOM, KEN, TZA, MOZ, MWI, ZMB, ZWE)

| Method | Total Runtime | Cost | Notes |
|--------|---------------|------|-------|
| **Local VM (sequential)** | 64 hours (8 × 8h) | $192 | One country at a time |
| **VM Image (manual parallel)** | 8 hours (manual setup) | $24 + setup time | You manage parallelism |
| **Container (sequential)** | 64 hours | $154 | Auto-cleanup, pay-per-second |
| **Batch (parallel)** | 8 hours | $24-26 | **BEST** - Full automation |

**Winner:** Azure Batch saves 56 hours and enables easy scaling to 50+ countries.

---

## Troubleshooting

### VM Image

**Problem:** SSH connection refused
```bash
# Check VM is running
az vm get-instance-view -g mosaic-rg -n mosaic-vm --query instanceView.statuses[1]

# Start if stopped
az vm start -g mosaic-rg -n mosaic-vm
```

**Problem:** RStudio won't load
```bash
# Check NSG allows port 8787
az network nsg rule list -g mosaic-rg --nsg-name mosaic-vm-nsg --query "[?destinationPortRange=='8787']"

# Restart RStudio Server
ssh mosaicuser@$VM_IP
sudo systemctl restart rstudio-server
```

### Container

**Problem:** Container fails to start
```bash
# Check container logs
az container logs -g mosaic-rg -n mosaic-som

# Common issue: Registry credentials
az acr credential show --name mosaicidm
```

**Problem:** Out of memory
```bash
# Increase memory allocation
az container create ... --memory 512  # Up from 456GB
```

### Batch

**Problem:** Tasks stuck in "active" state
```bash
# Check pool status
az batch pool show --pool-id mosaic-hpc-pool

# Resize pool manually
az batch pool resize --pool-id mosaic-hpc-pool --target-dedicated-nodes 4
```

**Problem:** Container pull errors
```bash
# Update container registry credentials
# Re-run setup-batch-account.sh
```

---

## Next Steps

1. **Test with small run first:**
   - Use `N_SIMULATIONS=100` for testing
   - Verify outputs before full run

2. **Monitor costs:**
   ```bash
   # Set up cost alerts in Azure portal
   # Monitor: Cost Management → Cost alerts
   ```

3. **Automate with CI/CD:**
   - Add GitHub Actions workflow
   - See `../.github/workflows/` for examples

4. **Scale to production:**
   - Batch: Scale to 20+ simultaneous countries
   - VM Image: Create scheduled start/stop
   - Container: Integrate with Azure Functions for event-driven runs

---

## Support

- **Issues:** https://github.com/InstituteforDiseaseModeling/MOSAIC-pkg/issues
- **Docs:** https://institutefordiseasemodeling.github.io/MOSAIC-docs/
- **Azure Batch Docs:** https://docs.microsoft.com/azure/batch/
