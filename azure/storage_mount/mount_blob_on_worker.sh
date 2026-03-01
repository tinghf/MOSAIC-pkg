#!/bin/bash
# Mount Azure Blob Storage using BlobFuse2 on Coiled worker
# Works in unprivileged containers (no CAP_SYS_ADMIN needed!)

set -e

STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT:-ttingeasyva}"
STORAGE_KEY="${AZURE_STORAGE_KEY}"
CONTAINER="${AZURE_BLOB_CONTAINER:-mosaic-data}"
MOUNT_POINT="/workspace/MOSAIC"
CONFIG_FILE="/tmp/blobfuse-config.yaml"

echo "========================================================================"
echo "Mounting Azure Blob Storage with BlobFuse2"
echo "========================================================================"

# Check if credentials are available
if [ -z "$STORAGE_KEY" ]; then
    echo "❌ ERROR: AZURE_STORAGE_KEY environment variable not set"
    exit 1
fi

# Create BlobFuse config file
cat > "$CONFIG_FILE" <<EOF
allow-other: true

logging:
  type: syslog
  level: log_warning

components:
  - libfuse
  - file_cache
  - attr_cache
  - azstorage

libfuse:
  attribute-expiration-sec: 120
  entry-expiration-sec: 120
  negative-entry-expiration-sec: 240

file_cache:
  path: /tmp/blobfuse-cache
  timeout-sec: 120
  max-size-mb: 4096

attr_cache:
  timeout-sec: 7200

azstorage:
  type: block
  account-name: $STORAGE_ACCOUNT
  account-key: $STORAGE_KEY
  endpoint: https://$STORAGE_ACCOUNT.blob.core.windows.net
  mode: key
  container: $CONTAINER
EOF

echo "✅ BlobFuse config created"

# Create cache and mount directories
mkdir -p /tmp/blobfuse-cache
mkdir -p "$MOUNT_POINT"
echo "✅ Directories created"

# Mount using BlobFuse2
echo "Mounting blob container '$CONTAINER'..."
blobfuse2 mount "$MOUNT_POINT" --config-file="$CONFIG_FILE"

# Verify mount
if [ ! -d "$MOUNT_POINT/MOSAIC/MOSAIC-data" ]; then
    echo "❌ ERROR: Mount failed - MOSAIC-data not found"
    ls -la "$MOUNT_POINT"
    exit 1
fi

if [ ! -d "$MOUNT_POINT/MOSAIC/MOSAIC-pkg" ]; then
    echo "❌ ERROR: Mount failed - MOSAIC-pkg not found"
    ls -la "$MOUNT_POINT"
    exit 1
fi

echo "✅ Blob storage mounted successfully"
echo "   Mount point: $MOUNT_POINT"
echo "   MOSAIC-data: $(du -sh $MOUNT_POINT/MOSAIC/MOSAIC-data 2>/dev/null | cut -f1 || echo 'checking...')"
echo "   MOSAIC-pkg:  $(du -sh $MOUNT_POINT/MOSAIC/MOSAIC-pkg 2>/dev/null | cut -f1 || echo 'checking...')"
echo "========================================================================"
