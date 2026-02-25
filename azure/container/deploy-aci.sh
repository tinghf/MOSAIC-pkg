#!/bin/bash
# ==============================================================================
# Deploy MOSAIC Container to Azure Container Instances
# ==============================================================================
# Run MOSAIC calibration as a one-off container job
#
# Prerequisites:
#   - Azure CLI logged in (az login)
#   - Container image pushed to ACR
#   - Azure Files storage account for outputs (optional)
#
# Usage:
#   bash deploy-aci.sh [iso-code] [container-name] [cores] [memory-gb]
#
# ==============================================================================

set -e

# Arguments
ISO_CODE="${1:-SOM}"
CONTAINER_NAME="${2:-mosaic-${ISO_CODE}-$(date +%Y%m%d-%H%M%S)}"
CORES="${3:-120}"
MEMORY_GB="${4:-456}"

# Configuration
RESOURCE_GROUP="mosaic-rg"
REGISTRY_NAME="mosaicidm"
IMAGE_NAME="mosaic"
IMAGE_TAG="latest"
STORAGE_ACCOUNT="mosaicstorage"
STORAGE_SHARE="outputs"

echo "======================================"
echo "MOSAIC ACI Deployment"
echo "======================================"
echo "ISO Code: $ISO_CODE"
echo "Container: $CONTAINER_NAME"
echo "Resources: ${CORES} cores, ${MEMORY_GB}GB RAM"
echo "Image: ${REGISTRY_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"
echo "======================================"
echo ""

# Create resource group if it doesn't exist
az group create --name "$RESOURCE_GROUP" --location eastus --output none || true

# Get registry credentials
echo "[1/3] Getting registry credentials..."
REGISTRY_USERNAME=$(az acr credential show \
  --name "$REGISTRY_NAME" \
  --query username -o tsv)

REGISTRY_PASSWORD=$(az acr credential show \
  --name "$REGISTRY_NAME" \
  --query "passwords[0].value" -o tsv)

# Get storage account key (if using Azure Files)
if az storage account show --name "$STORAGE_ACCOUNT" &>/dev/null; then
  echo "[2/3] Configuring Azure Files output volume..."
  STORAGE_KEY=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT" \
    --query "[0].value" -o tsv)

  # Ensure file share exists
  az storage share create \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$STORAGE_KEY" \
    --name "$STORAGE_SHARE" \
    --output none || true

  VOLUME_MOUNT="--azure-file-volume-account-name $STORAGE_ACCOUNT \
    --azure-file-volume-account-key $STORAGE_KEY \
    --azure-file-volume-share-name $STORAGE_SHARE \
    --azure-file-volume-mount-path /outputs"
else
  echo "[2/3] No storage account configured - outputs will stay in container"
  VOLUME_MOUNT=""
fi

# Deploy container
echo "[3/3] Deploying container..."
az container create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINER_NAME" \
  --image "${REGISTRY_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}" \
  --registry-login-server "${REGISTRY_NAME}.azurecr.io" \
  --registry-username "$REGISTRY_USERNAME" \
  --registry-password "$REGISTRY_PASSWORD" \
  --cpu "$CORES" \
  --memory "$MEMORY_GB" \
  --restart-policy Never \
  --environment-variables \
    ISO_CODE="$ISO_CODE" \
    N_SIMULATIONS=1000 \
    N_ITERATIONS=3 \
    N_CORES="$CORES" \
    TARGET_R2=0.95 \
    ENABLE_NPE=FALSE \
  $VOLUME_MOUNT \
  --output table

echo ""
echo "======================================"
echo "Container deployed!"
echo "======================================"
echo ""
echo "Monitor logs:"
echo "  az container logs --follow -g $RESOURCE_GROUP -n $CONTAINER_NAME"
echo ""
echo "Check status:"
echo "  az container show -g $RESOURCE_GROUP -n $CONTAINER_NAME --query instanceView.state"
echo ""
echo "Attach to container:"
echo "  az container attach -g $RESOURCE_GROUP -n $CONTAINER_NAME"
echo ""
echo "Download outputs (if using Azure Files):"
echo "  az storage file download-batch \\"
echo "    --account-name $STORAGE_ACCOUNT \\"
echo "    --source $STORAGE_SHARE \\"
echo "    --destination ./outputs/"
echo ""
echo "Delete container when done:"
echo "  az container delete -g $RESOURCE_GROUP -n $CONTAINER_NAME --yes"
echo ""

# Follow logs automatically
echo "Following container logs (Ctrl+C to detach)..."
echo ""
sleep 3
az container logs --follow -g "$RESOURCE_GROUP" -n "$CONTAINER_NAME" || true
