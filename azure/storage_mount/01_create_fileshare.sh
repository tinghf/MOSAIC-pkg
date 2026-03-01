#!/bin/bash
# Create Azure File Share for MOSAIC data
# This allows Coiled workers to mount shared data

set -e

STORAGE_ACCOUNT="ttingeasyva"
RESOURCE_GROUP="tting-easyva-test-rg"
FILE_SHARE_NAME="mosaic-shared-data"
QUOTA_GB=5  # 5GB quota (plenty for 150MB data)

echo "========================================================================"
echo "Creating Azure File Share for MOSAIC Data"
echo "========================================================================"
echo "Storage Account: $STORAGE_ACCOUNT"
echo "Resource Group:  $RESOURCE_GROUP"
echo "File Share:      $FILE_SHARE_NAME"
echo "Quota:           ${QUOTA_GB}GB"
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

# Check if file share already exists
echo "Checking if file share already exists..."
if az storage share exists \
    --account-name "$STORAGE_ACCOUNT" \
    --name "$FILE_SHARE_NAME" \
    --query "exists" -o tsv | grep -q "true"; then
    echo "⚠️  File share '$FILE_SHARE_NAME' already exists"
    echo "   To delete and recreate: az storage share delete --name $FILE_SHARE_NAME --account-name $STORAGE_ACCOUNT"
    echo "   To keep and populate: Skip to step 02_populate_fileshare.sh"
    exit 0
fi

# Create file share
echo "Creating file share..."
az storage share create \
    --account-name "$STORAGE_ACCOUNT" \
    --name "$FILE_SHARE_NAME" \
    --quota "$QUOTA_GB" \
    --output table

echo ""
echo "========================================================================"
echo "✅ File share created successfully!"
echo "========================================================================"
echo "Name:     $FILE_SHARE_NAME"
echo "Account:  $STORAGE_ACCOUNT"
echo "Quota:    ${QUOTA_GB}GB"
echo ""
echo "Next step: Run ./02_populate_fileshare.sh to upload MOSAIC data"
echo "========================================================================"
