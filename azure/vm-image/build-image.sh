#!/bin/bash
# ==============================================================================
# MOSAIC Azure VM Image Builder
# ==============================================================================
# Creates a custom Azure VM image with MOSAIC pre-installed
#
# Prerequisites:
#   - Azure CLI installed and logged in (az login)
#   - Contributor role on target subscription
#   - Image gallery created (or use managed image directly)
#
# Usage:
#   bash build-image.sh [--gallery mosaic-gallery] [--version 0.13.24]
#
# ==============================================================================

set -e

# Parse arguments
GALLERY_NAME="${1:-mosaic-gallery}"
IMAGE_VERSION="${2:-0.13.24}"
RESOURCE_GROUP="${3:-mosaic-images-rg}"
LOCATION="${4:-eastus}"
IMAGE_NAME="mosaic-ubuntu2004"
BUILD_VM="mosaic-image-builder-$(date +%s)"

echo "======================================"
echo "MOSAIC Image Builder"
echo "======================================"
echo "Gallery: $GALLERY_NAME"
echo "Image: $IMAGE_NAME"
echo "Version: $IMAGE_VERSION"
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo ""

# Create resource group if it doesn't exist
echo "[1/8] Creating resource group..."
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output table

# Create temporary VM for image building
echo "[2/8] Creating builder VM (Ubuntu 20.04, Standard_D8s_v3)..."
az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$BUILD_VM" \
  --image Canonical:0001-com-ubuntu-server-focal:20_04-lts-gen2:latest \
  --size Standard_D8s_v3 \
  --admin-username mosaicuser \
  --generate-ssh-keys \
  --output table

# Get VM IP address
BUILD_VM_IP=$(az vm show -d \
  --resource-group "$RESOURCE_GROUP" \
  --name "$BUILD_VM" \
  --query publicIps -o tsv)

echo "Builder VM created: $BUILD_VM_IP"
echo "Waiting 30 seconds for VM to fully initialize..."
sleep 30

# Copy setup script to VM
echo "[3/8] Copying MOSAIC setup script to builder VM..."
scp -o StrictHostKeyChecking=no \
  ../../vm/setup_mosaic.sh \
  mosaicuser@${BUILD_VM_IP}:/tmp/setup_mosaic.sh

# Run setup script on VM
echo "[4/8] Running MOSAIC setup (this will take 20-30 minutes)..."
ssh -o StrictHostKeyChecking=no mosaicuser@${BUILD_VM_IP} << 'EOF'
  cd /tmp
  chmod +x setup_mosaic.sh
  bash setup_mosaic.sh

  # Clone MOSAIC-pkg repo
  mkdir -p ~/MOSAIC
  cd ~/MOSAIC
  git clone https://github.com/InstituteforDiseaseModeling/MOSAIC-pkg.git

  # Optional: Clone MOSAIC-data (commented out - large download)
  # git clone https://github.com/InstituteforDiseaseModeling/MOSAIC-data.git

  # Install RStudio Server for interactive access
  sudo apt-get install -y gdebi-core
  wget https://download2.rstudio.org/server/jammy/amd64/rstudio-server-2023.12.1-402-amd64.deb
  sudo gdebi -n rstudio-server-2023.12.1-402-amd64.deb

  # Configure RStudio to start on boot
  sudo systemctl enable rstudio-server

  # Set user password for RStudio login
  echo "mosaicuser:mosaic2024" | sudo chpasswd

  # Create welcome message
  cat > ~/.bash_profile << 'WELCOME'
echo "======================================"
echo "MOSAIC Research Environment"
echo "======================================"
echo "MOSAIC version: $(Rscript -e "cat(as.character(packageVersion('MOSAIC')))" 2>/dev/null)"
echo "R version: $(R --version | head -1)"
echo "Python version: $(python3 --version)"
echo ""
echo "Quick start:"
echo "  cd ~/MOSAIC/MOSAIC-pkg"
echo "  Rscript vm/launch_mosaic.R"
echo ""
echo "RStudio Server: http://$(hostname -I | awk '{print $1}'):8787"
echo "  Username: mosaicuser"
echo "  Password: mosaic2024"
echo "======================================"
WELCOME

  # Clean up installation artifacts
  sudo apt-get clean
  rm -rf /tmp/*

  echo "MOSAIC setup complete!"
EOF

# Generalize VM for imaging
echo "[5/8] Generalizing VM..."
ssh mosaicuser@${BUILD_VM_IP} << 'EOF'
  # Waagent deprovision (Azure-specific cleanup)
  sudo waagent -deprovision+user -force
EOF

# Deallocate and generalize VM in Azure
echo "[6/8] Deallocating and generalizing VM in Azure..."
az vm deallocate \
  --resource-group "$RESOURCE_GROUP" \
  --name "$BUILD_VM"

az vm generalize \
  --resource-group "$RESOURCE_GROUP" \
  --name "$BUILD_VM"

# Create managed image
echo "[7/8] Creating managed image..."
az image create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$IMAGE_NAME" \
  --source "$BUILD_VM" \
  --output table

# Optional: Create image gallery and publish image definition
if [ -n "$GALLERY_NAME" ]; then
  echo "[8/8] Publishing to Azure Compute Gallery..."

  # Create gallery if it doesn't exist
  az sig create \
    --resource-group "$RESOURCE_GROUP" \
    --gallery-name "$GALLERY_NAME" \
    --location "$LOCATION" || true

  # Create image definition
  az sig image-definition create \
    --resource-group "$RESOURCE_GROUP" \
    --gallery-name "$GALLERY_NAME" \
    --gallery-image-definition "$IMAGE_NAME" \
    --publisher InstituteforDiseaseModeling \
    --offer MOSAIC \
    --sku Ubuntu-20.04-MOSAIC \
    --os-type Linux \
    --os-state Specialized \
    --hyper-v-generation V2 || true

  # Create image version
  IMAGE_ID=$(az image show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$IMAGE_NAME" \
    --query id -o tsv)

  az sig image-version create \
    --resource-group "$RESOURCE_GROUP" \
    --gallery-name "$GALLERY_NAME" \
    --gallery-image-definition "$IMAGE_NAME" \
    --gallery-image-version "$IMAGE_VERSION" \
    --managed-image "$IMAGE_ID" \
    --replica-count 1 \
    --output table
fi

# Clean up builder VM
echo "Cleaning up builder VM..."
az vm delete \
  --resource-group "$RESOURCE_GROUP" \
  --name "$BUILD_VM" \
  --yes

echo ""
echo "======================================"
echo "Image creation complete!"
echo "======================================"
echo ""
echo "Image Details:"
echo "  Name: $IMAGE_NAME"
echo "  Resource Group: $RESOURCE_GROUP"
if [ -n "$GALLERY_NAME" ]; then
  echo "  Gallery: $GALLERY_NAME"
  echo "  Version: $IMAGE_VERSION"
fi
echo ""
echo "Next steps:"
echo "  1. Deploy VM from image:"
echo "     az vm create \\"
echo "       --resource-group mosaic-rg \\"
echo "       --name mosaic-vm \\"
echo "       --image /subscriptions/<subscription-id>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/images/$IMAGE_NAME \\"
echo "       --size Standard_HB120rs_v3 \\"
echo "       --admin-username mosaicuser \\"
echo "       --generate-ssh-keys"
echo ""
echo "  2. Or use the Bicep template:"
echo "     az deployment group create \\"
echo "       --resource-group mosaic-rg \\"
echo "       --template-file deploy.bicep"
echo ""
