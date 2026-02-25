# MOSAIC VM Image Deployment

Pre-configured Azure VM images with MOSAIC fully installed and ready to use.

## Overview

This option creates a **custom VM image** with:
- ✅ R 4.1+ with all packages pre-installed
- ✅ Python 3.11 with conda environment configured
- ✅ MOSAIC package installed and verified
- ✅ RStudio Server for interactive development
- ✅ All system dependencies (GDAL, PROJ, GEOS, HDF5)
- ✅ Git repos cloned and ready

## When to Use This

**Best for:**
- Interactive development and debugging
- Learning MOSAIC with RStudio GUI
- Ad-hoc calibration runs
- Experimenting with parameter changes

**Not ideal for:**
- Fully automated workflows (use Container instead)
- Massive parallel runs (use Batch instead)
- Cost-sensitive production (use Container with auto-cleanup)

## Setup (One-Time)

### Prerequisites

```bash
# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Login to Azure
az login

# Set default subscription (if needed)
az account set --subscription "Your Subscription Name"
```

### Build the Image

```bash
cd azure/vm-image

# Build image (takes ~30 minutes)
bash build-image.sh

# Optional: Specify custom settings
bash build-image.sh my-gallery 0.13.24 my-rg westus2
```

This creates:
1. Temporary VM with Ubuntu 20.04
2. Runs `vm/setup_mosaic.sh` to install MOSAIC
3. Installs RStudio Server
4. Generalizes and captures VM image
5. Publishes to Azure Compute Gallery (optional)

## Deploy a VM from Image

### Option A: Using Bicep Template (Recommended)

```bash
# 1. Edit parameters
nano parameters.json
# Update:
#   - sshPublicKey (paste your ~/.ssh/id_rsa.pub)
#   - vmSize (choose from allowed sizes)
#   - shutdownTime (UTC time for auto-shutdown)

# 2. Create resource group
az group create --name mosaic-rg --location eastus

# 3. Deploy VM
az deployment group create \
  --resource-group mosaic-rg \
  --template-file deploy.bicep \
  --parameters @parameters.json

# 4. Get connection info
az deployment group show \
  --resource-group mosaic-rg \
  --name deploy \
  --query properties.outputs
```

### Option B: Manual Creation

```bash
# Get image ID
IMAGE_ID=$(az image show \
  --resource-group mosaic-images-rg \
  --name mosaic-ubuntu2004 \
  --query id -o tsv)

# Create VM
az vm create \
  --resource-group mosaic-rg \
  --name mosaic-vm \
  --image "$IMAGE_ID" \
  --size Standard_HB120rs_v3 \
  --admin-username mosaicuser \
  --generate-ssh-keys
```

## VM Size Options

| Size | vCPUs | RAM | Cost/hr | Best For |
|------|-------|-----|---------|----------|
| Standard_HB120rs_v3 | 120 | 448GB | $3.00 | Production runs (recommended) |
| Standard_HB120-96rs_v3 | 96 | 448GB | $2.40 | Medium-large calibrations |
| Standard_D32s_v3 | 32 | 128GB | $1.54 | Development/testing |
| Standard_D16s_v3 | 16 | 64GB | $0.77 | Small runs, learning |

**Tip:** Use smaller sizes for development, then scale up for production.

## Using the VM

### SSH Access

```bash
# Get IP address
VM_IP=$(az vm show -d \
  --resource-group mosaic-rg \
  --name mosaic-vm \
  --query publicIps -o tsv)

# SSH into VM
ssh mosaicuser@$VM_IP

# Check MOSAIC installation
Rscript -e 'library(MOSAIC); check_dependencies()'
```

### RStudio Server Access

```bash
# Open in browser
echo "http://$VM_IP:8787"

# Default credentials
# Username: mosaicuser
# Password: mosaic2024
```

**Security Note:** Change the password after first login:
```bash
ssh mosaicuser@$VM_IP
passwd  # Enter new password
```

### Running MOSAIC

#### Option 1: Via SSH

```bash
ssh mosaicuser@$VM_IP

# Navigate to MOSAIC directory
cd ~/MOSAIC/MOSAIC-pkg

# Edit launch script if needed
nano vm/launch_mosaic.R

# Run calibration
Rscript vm/launch_mosaic.R

# Or use screen to keep running after disconnect
screen -S mosaic
Rscript vm/launch_mosaic.R
# Press Ctrl+A then D to detach
# Reconnect with: screen -r mosaic
```

#### Option 2: Via RStudio

1. Open `http://$VM_IP:8787` in browser
2. Login with credentials
3. Open File → Open File → `~/MOSAIC/MOSAIC-pkg/vm/launch_mosaic.R`
4. Modify parameters as needed
5. Run script (Ctrl+Shift+Enter)

### Downloading Results

```bash
# From your local machine
scp -r mosaicuser@$VM_IP:~/MOSAIC/output/SOM ./outputs/

# Or download compressed archive
ssh mosaicuser@$VM_IP "cd ~/MOSAIC/output && tar -czf SOM.tar.gz SOM/"
scp mosaicuser@$VM_IP:~/MOSAIC/output/SOM.tar.gz ./
```

## Cost Management

### Auto-Shutdown

The Bicep template includes auto-shutdown at 2 AM UTC by default.

**Customize shutdown time:**
```json
// In parameters.json
"shutdownTime": {"value": "0200"},  // 2 AM UTC
"shutdownTimezone": {"value": "Pacific Standard Time"}
```

### Manual Start/Stop

```bash
# Stop VM (deallocate - no charges while stopped)
az vm deallocate -g mosaic-rg -n mosaic-vm

# Start VM
az vm start -g mosaic-rg -n mosaic-vm

# Check status
az vm get-instance-view \
  -g mosaic-rg \
  -n mosaic-vm \
  --query instanceView.statuses[1]
```

### Cost Monitoring

```bash
# View current month costs for resource group
az consumption usage list \
  --start-date 2026-02-01 \
  --end-date 2026-02-28 \
  --query "[?contains(instanceId,'mosaic-rg')]" \
  --output table
```

## Updating the Image

When MOSAIC package updates:

```bash
# 1. Create new image version
bash build-image.sh mosaic-gallery 0.13.25

# 2. Update existing VMs
az vm deallocate -g mosaic-rg -n mosaic-vm
az vm generalize -g mosaic-rg -n mosaic-vm

# 3. Or delete old VM and redeploy
az vm delete -g mosaic-rg -n mosaic-vm --yes
az deployment group create \
  --resource-group mosaic-rg \
  --template-file deploy.bicep \
  --parameters @parameters.json
```

## Troubleshooting

### Issue: "Image not found"

```bash
# List available images
az image list \
  --resource-group mosaic-images-rg \
  --output table

# Check if image build completed
az image show \
  --resource-group mosaic-images-rg \
  --name mosaic-ubuntu2004
```

### Issue: "SSH connection refused"

```bash
# Check VM is running
az vm get-instance-view \
  -g mosaic-rg \
  -n mosaic-vm \
  --query instanceView.statuses

# Check NSG allows SSH
az network nsg rule list \
  -g mosaic-rg \
  --nsg-name mosaic-vm-nsg \
  --query "[?name=='SSH']"
```

### Issue: "RStudio Server not accessible"

```bash
# SSH into VM and check service
ssh mosaicuser@$VM_IP
sudo systemctl status rstudio-server

# Restart if needed
sudo systemctl restart rstudio-server

# Check firewall allows port 8787
az network nsg rule list \
  -g mosaic-rg \
  --nsg-name mosaic-vm-nsg \
  --query "[?destinationPortRange=='8787']"
```

### Issue: "Out of disk space"

```bash
# Check disk usage
ssh mosaicuser@$VM_IP
df -h

# Clean up old outputs
rm -rf ~/MOSAIC/output/old_runs/

# Or resize disk
az vm deallocate -g mosaic-rg -n mosaic-vm
az disk update \
  --resource-group mosaic-rg \
  --name mosaic-vm_OsDisk \
  --size-gb 512
az vm start -g mosaic-rg -n mosaic-vm
```

## Advanced: Scheduled Runs

Create a cron job to run MOSAIC automatically:

```bash
ssh mosaicuser@$VM_IP

# Edit crontab
crontab -e

# Add line (runs daily at 1 AM)
0 1 * * * /usr/bin/Rscript ~/MOSAIC/MOSAIC-pkg/vm/launch_mosaic.R >> ~/mosaic_cron.log 2>&1
```

## Cleanup

Delete VM (keeps image for future use):
```bash
az vm delete -g mosaic-rg -n mosaic-vm --yes
```

Delete entire resource group (including image):
```bash
az group delete -g mosaic-rg --yes --no-wait
az group delete -g mosaic-images-rg --yes --no-wait
```

## Next Steps

- **Scale up:** Use larger VM sizes for production
- **Automate:** Set up scheduled start/stop with Azure Automation
- **Share:** Export image to share with collaborators
- **Upgrade:** Rebuild image when MOSAIC updates

For automated workflows, consider migrating to **Container** or **Batch** options.
