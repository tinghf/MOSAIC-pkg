#!/bin/bash
# Create Azure Blob Storage container for MOSAIC data
# BlobFuse works in unprivileged containers (unlike CIFS/Azure Files)

set -e

STORAGE_ACCOUNT="ttingeasyva"
RESOURCE_GROUP="tting-easyva-test-rg"
CONTAINER_NAME="mosaic-data"

echo "========================================================================"
echo "Creating Azure Blob Container for MOSAIC Data"
echo "========================================================================"
echo "Storage Account: $STORAGE_ACCOUNT"
echo "Resource Group:  $RESOURCE_GROUP"
echo "Container:       $CONTAINER_NAME"
echo "========================================================================"
echo ""

# Verify we're logged in
echo "Verifying Azure login..."
az account show --query "name" -o tsv > /dev/null || {
    echo "❌ Not logged in to Azure. Run: az login"
    exit 1
}
echo "✅ Azure login verified"
echo ""

# Check if container already exists
echo "Checking if blob container already exists..."
if az storage container exists \
    --account-name "$STORAGE_ACCOUNT" \
    --name "$CONTAINER_NAME" \
    --query "exists" -o tsv | grep -q "true"; then
    echo "⚠️  Container '$CONTAINER_NAME' already exists"
    echo "   To delete and recreate: az storage container delete --name $CONTAINER_NAME --account-name $STORAGE_ACCOUNT"
    echo "   To keep and populate: Skip to step 05_upload_to_blob.sh"
    exit 0
fi

# Create blob container
echo "Creating blob container..."
az storage container create \
    --account-name "$STORAGE_ACCOUNT" \
    --name "$CONTAINER_NAME" \
    --public-access off \
    --output table

echo ""
echo "========================================================================"
echo "✅ Blob container created successfully!"
echo "========================================================================"
echo "Container: $CONTAINER_NAME"
echo "Account:   $STORAGE_ACCOUNT"
echo "Access:    Private (requires credentials)"
echo ""
echo "Next step: Run ./05_upload_to_blob.sh to upload MOSAIC data"
echo "========================================================================"
