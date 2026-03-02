#!/bin/bash
# Quick test: Run MOSAIC on Coiled with Azure Files mounted
# This tests the full end-to-end workflow with mounted storage

set -e

cd ~/MOSAIC/MOSAIC-pkg

# Source Azure credentials
if [ ! -f "azure/storage_mount/.env" ]; then
    echo "❌ ERROR: Credentials file not found"
    echo "   Run: ./03_get_mount_credentials.sh first"
    exit 1
fi

echo "Loading Azure credentials..."
set -a  # Export all variables
source azure/storage_mount/.env
set +a
echo "✅ Credentials loaded"
echo ""

# Verify credentials
if [ -z "$AZURE_STORAGE_KEY" ]; then
    echo "❌ ERROR: AZURE_STORAGE_KEY not set"
    exit 1
fi
echo "   Storage Account: $AZURE_STORAGE_ACCOUNT"
echo "   File Share: $AZURE_FILE_SHARE"
echo ""

# Activate conda environment
echo "Activating mosaic-coiled environment..."
source ~/miniforge3/etc/profile.d/conda.sh
conda activate mosaic-coiled
echo "✅ Environment activated"
echo ""

# Run MOSAIC on Coiled
echo "========================================================================"
echo "Running MOSAIC on Coiled with Azure Files Mount"
echo "========================================================================"
echo "Test parameters:"
echo "  - Country: ETH"
echo "  - Simulations: 10"
echo "  - Iterations: 1"
echo "  - Data Source: Azure Files (mounted on workers)"
echo "========================================================================"
echo ""

python azure/run_mosaic_parallel_country.py \
  --iso ETH \
  --n-simulations 100 \
  --n-iterations 1 \
  --output-dir ./coiled-mount-test \
  --coiled-env mosaic-docker-workers \
  --vm-type Standard_D4s_v6

echo ""
echo "========================================================================"
echo "Test complete! Check results in: ./coiled-mount-test/"
echo "========================================================================"
