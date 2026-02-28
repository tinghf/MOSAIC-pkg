#!/bin/bash
# Test script for local Coiled.io setup validation

set -e  # Exit on error

echo "======================================"
echo "MOSAIC Coiled.io Setup Validation"
echo "======================================"
echo ""

# Check Python
echo "1. Checking Python installation..."
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version)
    echo "   ✅ $PYTHON_VERSION"
else
    echo "   ❌ Python 3 not found. Please install Python 3.11+"
    exit 1
fi

# Check required Python packages
echo ""
echo "2. Checking Python packages..."
for package in coiled dask distributed pandas pyarrow; do
    if python3 -c "import $package" 2>/dev/null; then
        echo "   ✅ $package"
    else
        echo "   ❌ $package not installed. Run: pip install $package"
        exit 1
    fi
done

# Check Coiled authentication
echo ""
echo "3. Checking Coiled authentication..."
if [ -f ~/.coiled/token ]; then
    echo "   ✅ Coiled token found at ~/.coiled/token"
else
    echo "   ⚠️  Coiled token not found. Run: coiled login"
    exit 1
fi

# Test Coiled connection
echo ""
echo "4. Testing Coiled connection..."
if python3 -c "import coiled; print(f'   ✅ Connected to Coiled ({coiled.__version__})')"; then
    echo "   ✅ Coiled connection successful"
else
    echo "   ❌ Failed to connect to Coiled"
    exit 1
fi

# Check if mosaic-pkg environment exists
echo ""
echo "5. Checking for mosaic-pkg software environment..."
if python3 -c "import coiled; envs = coiled.list_software_environments(); 'mosaic-pkg' in envs" 2>/dev/null; then
    echo "   ✅ mosaic-pkg environment found"
else
    echo "   ⚠️  mosaic-pkg environment not found"
    echo "      Create it with: coiled env create --name mosaic-pkg --file azure/coiled_environment.yml --post-build azure/coiled_setup.sh"
    echo "      This takes 15-30 minutes (one-time)"
fi

# Summary
echo ""
echo "======================================"
echo "Validation Complete!"
echo "======================================"
echo ""
echo "Next steps:"
echo "  1. If mosaic-pkg environment doesn't exist, create it (see message above)"
echo "  2. Test small run: python azure/run_mosaic_coiled.py --iso ETH --n-simulations 100 --n-iterations 1 --n-workers 2 --output-dir ./test-output"
echo "  3. Expected cost: ~\$2, Runtime: 5 minutes"
echo ""
echo "For full setup instructions, see: azure/COILED_QUICKSTART.md"
echo ""
