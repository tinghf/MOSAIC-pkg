#!/bin/bash
# Mount Azure File Share on Coiled worker
# This script runs on each worker before MOSAIC execution

set -e

STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT:-ttingeasyva}"
STORAGE_KEY="${AZURE_STORAGE_KEY}"
FILE_SHARE="${AZURE_FILE_SHARE:-mosaic-shared-data}"
MOUNT_POINT="/workspace/MOSAIC"

echo "========================================================================"
echo "Mounting Azure File Share on Worker"
echo "========================================================================"

# Check if credentials are available
if [ -z "$STORAGE_KEY" ]; then
    echo "❌ ERROR: AZURE_STORAGE_KEY environment variable not set"
    echo "   Set it with: export AZURE_STORAGE_KEY=<your-key>"
    exit 1
fi

# Install cifs-utils if not present
if ! command -v mount.cifs &> /dev/null; then
    echo "Installing cifs-utils..."
    apt-get update -qq && apt-get install -y -qq cifs-utils > /dev/null 2>&1
    echo "✅ cifs-utils installed"
fi

# Create mount point
mkdir -p "$MOUNT_POINT"
echo "✅ Mount point created: $MOUNT_POINT"

# Mount file share
echo "Mounting //$STORAGE_ACCOUNT.file.core.windows.net/$FILE_SHARE..."
mount -t cifs \
    "//$STORAGE_ACCOUNT.file.core.windows.net/$FILE_SHARE/MOSAIC" \
    "$MOUNT_POINT" \
    -o vers=3.0,username=$STORAGE_ACCOUNT,password=$STORAGE_KEY,dir_mode=0777,file_mode=0777,serverino,nosharesock

# Verify mount
if [ ! -d "$MOUNT_POINT/MOSAIC-data" ]; then
    echo "❌ ERROR: Mount failed - MOSAIC-data not found"
    ls -la "$MOUNT_POINT"
    exit 1
fi

if [ ! -d "$MOUNT_POINT/MOSAIC-pkg" ]; then
    echo "❌ ERROR: Mount failed - MOSAIC-pkg not found"
    ls -la "$MOUNT_POINT"
    exit 1
fi

echo "✅ Azure File Share mounted successfully"
echo "   MOSAIC-data: $(du -sh $MOUNT_POINT/MOSAIC-data | cut -f1)"
echo "   MOSAIC-pkg:  $(du -sh $MOUNT_POINT/MOSAIC-pkg | cut -f1)"
echo "========================================================================"
