#!/bin/bash
# Upload MOSAIC data to Azure Blob Storage
# Creates directory structure and uploads repos

set -e

STORAGE_ACCOUNT="ttingeasyva"
CONTAINER_NAME="mosaic-data"
LOCAL_MOSAIC_ROOT="$HOME/MOSAIC"

echo "========================================================================"
echo "Uploading MOSAIC Data to Azure Blob Storage"
echo "========================================================================"
echo "Container:    $CONTAINER_NAME"
echo "Local Source: $LOCAL_MOSAIC_ROOT"
echo "========================================================================"
echo ""

# Verify local directories exist
echo "Verifying local MOSAIC directories..."
if [ ! -d "$LOCAL_MOSAIC_ROOT/MOSAIC-data" ]; then
    echo "❌ Directory not found: $LOCAL_MOSAIC_ROOT/MOSAIC-data"
    exit 1
fi
if [ ! -d "$LOCAL_MOSAIC_ROOT/MOSAIC-pkg" ]; then
    echo "❌ Directory not found: $LOCAL_MOSAIC_ROOT/MOSAIC-pkg"
    exit 1
fi
echo "✅ Local directories verified"
echo ""

# Upload MOSAIC-data (150MB)
echo "Uploading MOSAIC-data (150MB - this may take 2-3 minutes)..."
az storage blob upload-batch \
    --account-name "$STORAGE_ACCOUNT" \
    --destination "$CONTAINER_NAME" \
    --destination-path "MOSAIC/MOSAIC-data" \
    --source "$LOCAL_MOSAIC_ROOT/MOSAIC-data" \
    --pattern "*" \
    --overwrite \
    --output table

echo ""
echo "Uploading MOSAIC-pkg/model directory..."
# Only upload the model directory from MOSAIC-pkg (contains input/output)
if [ -d "$LOCAL_MOSAIC_ROOT/MOSAIC-pkg/model" ]; then
    az storage blob upload-batch \
        --account-name "$STORAGE_ACCOUNT" \
        --destination "$CONTAINER_NAME" \
        --destination-path "MOSAIC/MOSAIC-pkg/model" \
        --source "$LOCAL_MOSAIC_ROOT/MOSAIC-pkg/model" \
        --pattern "*" \
        --overwrite \
        --output table
else
    echo "⚠️  Warning: $LOCAL_MOSAIC_ROOT/MOSAIC-pkg/model not found - skipping"
fi

echo ""
echo "========================================================================"
echo "✅ Blob storage populated successfully!"
echo "========================================================================"
echo "Structure created:"
echo "  MOSAIC/"
echo "  ├── MOSAIC-data/  (150MB - all data files)"
echo "  └── MOSAIC-pkg/   (model configs only)"
echo ""
echo "Verify upload:"
echo "  az storage blob list --account-name $STORAGE_ACCOUNT --container-name $CONTAINER_NAME --prefix MOSAIC --output table | head -20"
echo ""
echo "Next step: Update Dockerfile to install BlobFuse2"
echo "========================================================================"
