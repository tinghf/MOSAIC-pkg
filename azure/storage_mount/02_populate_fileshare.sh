#!/bin/bash
# Populate Azure File Share with MOSAIC-data and MOSAIC-pkg
# Creates directory structure and uploads repos

set -e

STORAGE_ACCOUNT="ttingeasyva"
FILE_SHARE_NAME="mosaic-shared-data"
LOCAL_MOSAIC_ROOT="$HOME/MOSAIC"

echo "========================================================================"
echo "Populating Azure File Share with MOSAIC Data"
echo "========================================================================"
echo "File Share:   $FILE_SHARE_NAME"
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

# Create directory structure in file share
echo "Creating directory structure in file share..."
az storage directory create \
    --account-name "$STORAGE_ACCOUNT" \
    --share-name "$FILE_SHARE_NAME" \
    --name "MOSAIC" \
    --output none
echo "  ✓ Created: MOSAIC/"

az storage directory create \
    --account-name "$STORAGE_ACCOUNT" \
    --share-name "$FILE_SHARE_NAME" \
    --name "MOSAIC/MOSAIC-data" \
    --output none
echo "  ✓ Created: MOSAIC/MOSAIC-data/"

az storage directory create \
    --account-name "$STORAGE_ACCOUNT" \
    --share-name "$FILE_SHARE_NAME" \
    --name "MOSAIC/MOSAIC-pkg" \
    --output none
echo "  ✓ Created: MOSAIC/MOSAIC-pkg/"
echo ""

# Upload MOSAIC-data (150MB)
echo "Uploading MOSAIC-data (150MB - this may take 2-3 minutes)..."
az storage file upload-batch \
    --account-name "$STORAGE_ACCOUNT" \
    --destination "$FILE_SHARE_NAME/MOSAIC/MOSAIC-data" \
    --source "$LOCAL_MOSAIC_ROOT/MOSAIC-data" \
    --pattern "*" \
    --output table

echo ""
echo "Uploading MOSAIC-pkg/model directory (contains default configs)..."
# Only upload the model directory from MOSAIC-pkg (contains input/output)
# Don't upload the entire pkg - just the data/config files MOSAIC needs
mkdir -p /tmp/mosaic-pkg-model
if [ -d "$LOCAL_MOSAIC_ROOT/MOSAIC-pkg/model" ]; then
    cp -r "$LOCAL_MOSAIC_ROOT/MOSAIC-pkg/model" /tmp/mosaic-pkg-model/
    az storage file upload-batch \
        --account-name "$STORAGE_ACCOUNT" \
        --destination "$FILE_SHARE_NAME/MOSAIC/MOSAIC-pkg" \
        --source "/tmp/mosaic-pkg-model" \
        --pattern "*" \
        --output table
    rm -rf /tmp/mosaic-pkg-model
else
    echo "⚠️  Warning: $LOCAL_MOSAIC_ROOT/MOSAIC-pkg/model not found - skipping"
    echo "   This is OK if you don't need custom model inputs"
fi

echo ""
echo "========================================================================"
echo "✅ File share populated successfully!"
echo "========================================================================"
echo "Structure created:"
echo "  MOSAIC/"
echo "  ├── MOSAIC-data/  (150MB - all data files)"
echo "  └── MOSAIC-pkg/   (model configs only)"
echo ""
echo "Verify upload:"
echo "  az storage file list --account-name $STORAGE_ACCOUNT --share-name $FILE_SHARE_NAME --path MOSAIC --output table"
echo ""
echo "Next step: Update Dockerfile to mount this file share"
echo "========================================================================"
