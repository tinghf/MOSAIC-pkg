#!/bin/bash
# Get Azure File Share credentials for mounting in Docker/Coiled
# Outputs environment variables needed for mounting

set -e

STORAGE_ACCOUNT="ttingeasyva"
RESOURCE_GROUP="tting-easyva-test-rg"
FILE_SHARE_NAME="mosaic-shared-data"

echo "========================================================================"
echo "Azure File Share Mount Credentials"
echo "========================================================================"
echo ""

# Get storage account key
echo "Retrieving storage account key..."
STORAGE_KEY=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[0].value" -o tsv)

if [ -z "$STORAGE_KEY" ]; then
    echo "❌ Failed to retrieve storage account key"
    exit 1
fi

echo "✅ Storage key retrieved"
echo ""

# Display credentials
echo "========================================================================"
echo "Mount Credentials (Use in Coiled/Docker)"
echo "========================================================================"
echo ""
echo "Storage Account:  $STORAGE_ACCOUNT"
echo "File Share:       $FILE_SHARE_NAME"
echo "Storage Key:      ${STORAGE_KEY:0:20}...${STORAGE_KEY: -20}"
echo ""
echo "========================================================================"
echo "Environment Variables for Coiled Workers"
echo "========================================================================"
echo ""
echo "export AZURE_STORAGE_ACCOUNT=\"$STORAGE_ACCOUNT\""
echo "export AZURE_STORAGE_KEY=\"$STORAGE_KEY\""
echo "export AZURE_FILE_SHARE=\"$FILE_SHARE_NAME\""
echo ""
echo "========================================================================"
echo "Mount Command for Linux"
echo "========================================================================"
echo ""
echo "# Install cifs-utils if needed"
echo "sudo apt-get install -y cifs-utils"
echo ""
echo "# Create mount point"
echo "sudo mkdir -p /mnt/mosaic-data"
echo ""
echo "# Mount file share"
echo "sudo mount -t cifs \\"
echo "  //$STORAGE_ACCOUNT.file.core.windows.net/$FILE_SHARE_NAME \\"
echo "  /mnt/mosaic-data \\"
echo "  -o vers=3.0,username=$STORAGE_ACCOUNT,password=$STORAGE_KEY,dir_mode=0777,file_mode=0777,serverino"
echo ""
echo "# Verify mount"
echo "ls -la /mnt/mosaic-data/MOSAIC/"
echo ""
echo "========================================================================"
echo "Docker Volume Mount (for local testing)"
echo "========================================================================"
echo ""
echo "docker run --rm \\"
echo "  -v /mnt/mosaic-data/MOSAIC:/workspace/MOSAIC \\"
echo "  ttingidmod/mosaic-worker:latest \\"
echo "  R -e \"library(MOSAIC); set_root_directory('/workspace/MOSAIC'); get_paths()\""
echo ""
echo "========================================================================"

# Save credentials to .env file for scripting
cat > "$(dirname "$0")/.env" <<EOF
# Azure File Share credentials for MOSAIC
# Generated: $(date)
# DO NOT COMMIT THIS FILE!

AZURE_STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
AZURE_STORAGE_KEY="$STORAGE_KEY"
AZURE_FILE_SHARE="$FILE_SHARE_NAME"
AZURE_STORAGE_URL="//$STORAGE_ACCOUNT.file.core.windows.net/$FILE_SHARE_NAME"
EOF

echo "Credentials saved to: azure/storage_mount/.env"
echo "⚠️  DO NOT COMMIT THIS FILE - Add to .gitignore!"
echo ""
