#!/bin/bash
# ==============================================================================
# Azure Batch Setup for MOSAIC
# ==============================================================================
# Creates Batch account, pools, and storage for parallel MOSAIC calibrations
#
# Prerequisites:
#   - Azure CLI logged in
#   - Contributor access to subscription
#
# Usage:
#   bash setup-batch-account.sh
#
# ==============================================================================

set -e

# Configuration
RESOURCE_GROUP="mosaic-batch-rg"
LOCATION="eastus"
BATCH_ACCOUNT="mosaicbatch"
STORAGE_ACCOUNT="mosaicbatchstorage"
POOL_ID="mosaic-hpc-pool"
CONTAINER_REGISTRY="mosaicidm"

echo "======================================"
echo "Azure Batch Setup for MOSAIC"
echo "======================================"
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo "Batch Account: $BATCH_ACCOUNT"
echo "======================================"
echo ""

# Create resource group
echo "[1/6] Creating resource group..."
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output table

# Create storage account for batch
echo "[2/6] Creating storage account..."
az storage account create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$STORAGE_ACCOUNT" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --output table

# Create batch account
echo "[3/6] Creating Batch account..."
az batch account create \
  --name "$BATCH_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --storage-account "$STORAGE_ACCOUNT" \
  --output table

# Login to batch account
echo "[4/6] Logging into Batch account..."
az batch account login \
  --name "$BATCH_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP"

# Create container configuration for pool
echo "[5/6] Configuring container registry..."

# Get ACR credentials
ACR_USERNAME=$(az acr credential show \
  --name "$CONTAINER_REGISTRY" \
  --query username -o tsv)

ACR_PASSWORD=$(az acr credential show \
  --name "$CONTAINER_REGISTRY" \
  --query "passwords[0].value" -o tsv)

ACR_LOGIN_SERVER="${CONTAINER_REGISTRY}.azurecr.io"

# Create HPC pool with container support
echo "[6/6] Creating HPC compute pool..."

cat > /tmp/pool-config.json <<EOF
{
  "id": "$POOL_ID",
  "vmSize": "Standard_HB120rs_v3",
  "virtualMachineConfiguration": {
    "imageReference": {
      "publisher": "microsoft-azure-batch",
      "offer": "ubuntu-server-container",
      "sku": "20-04-lts",
      "version": "latest"
    },
    "nodeAgentSkuId": "batch.node.ubuntu 20.04",
    "containerConfiguration": {
      "type": "dockerCompatible",
      "containerImageNames": [
        "${ACR_LOGIN_SERVER}/mosaic:latest"
      ],
      "containerRegistries": [
        {
          "registryServer": "$ACR_LOGIN_SERVER",
          "userName": "$ACR_USERNAME",
          "password": "$ACR_PASSWORD"
        }
      ]
    }
  },
  "targetDedicatedNodes": 0,
  "targetLowPriorityNodes": 0,
  "enableAutoScale": true,
  "autoScaleFormula": "\\$TargetDedicatedNodes = \\$PendingTasks.GetSample(10 * TimeInterval_Minute, 0);",
  "autoScaleEvaluationInterval": "PT5M"
}
EOF

az batch pool create \
  --json-file /tmp/pool-config.json

rm /tmp/pool-config.json

echo ""
echo "======================================"
echo "Batch setup complete!"
echo "======================================"
echo ""
echo "Batch Account Details:"
az batch account show \
  --name "$BATCH_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query "{name:name, location:location, poolQuota:poolQuota, dedicatedCoreQuota:dedicatedCoreQuota}" \
  --output table

echo ""
echo "Pool Details:"
az batch pool show \
  --pool-id "$POOL_ID" \
  --query "{id:id, vmSize:vmSize, state:allocationState, currentDedicated:currentDedicatedNodes}" \
  --output table

echo ""
echo "Next steps:"
echo "  1. Submit a job:"
echo "     python3 submit-mosaic-batch.py --countries SOM,ETH,KEN"
echo ""
echo "  2. Monitor job:"
echo "     python3 monitor-batch.py --job-id mosaic-calibration-001"
echo ""
echo "  3. Scale pool manually (if needed):"
echo "     az batch pool resize --pool-id $POOL_ID --target-dedicated-nodes 4"
echo ""
