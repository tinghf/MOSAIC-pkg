#!/usr/bin/env python
"""
Create Coiled software environment with MOSAIC pre-installed.
Uses undocumented post_build parameter to install MOSAIC after conda setup.

Usage:
    python azure/create_coiled_env.py
"""

import coiled
from pathlib import Path

# Paths
REPO_ROOT = Path(__file__).parent.parent
CONDA_ENV_FILE = REPO_ROOT / "azure" / "coiled_environment.yml"
POST_BUILD_SCRIPT = REPO_ROOT / "azure" / "coiled_setup.sh"

print("="*70)
print("Creating Coiled Software Environment with MOSAIC")
print("="*70)
print(f"Conda environment: {CONDA_ENV_FILE}")
print(f"Post-build script: {POST_BUILD_SCRIPT}")
print()

# Verify files exist
if not CONDA_ENV_FILE.exists():
    raise FileNotFoundError(f"Conda environment file not found: {CONDA_ENV_FILE}")

if not POST_BUILD_SCRIPT.exists():
    raise FileNotFoundError(f"Post-build script not found: {POST_BUILD_SCRIPT}")

# Create environment with post_build parameter
print("Creating environment (this will take 15-30 minutes)...")
print("Building base conda environment + running post-build script")
print()

try:
    # Try using post_build parameter (undocumented but exists in source)
    result = coiled.create_software_environment(
        name="mosaic-pkg-v2",
        conda=str(CONDA_ENV_FILE),
        region_name="westus2",
        force_rebuild=True,
        **{"post_build": str(POST_BUILD_SCRIPT)}  # Pass as kwarg to bypass signature check
    )

    print("="*70)
    print("✅ Environment created successfully!")
    print("="*70)
    print(f"Environment name: mosaic-pkg-v2")
    print(f"MOSAIC pre-installed: Yes")
    print()
    print("Next steps:")
    print("1. Update run_mosaic_coiled.py: SOFTWARE_ENV = 'mosaic-pkg-v2'")
    print("2. Remove _ensure_mosaic_installed() function (lines 150-209)")
    print("3. Test: python azure/run_mosaic_coiled.py --iso ETH --n-simulations 10 --n-workers 2")
    print("="*70)

except TypeError as e:
    if "post_build" in str(e):
        print("❌ Error: post_build parameter not supported in this Coiled version")
        print()
        print("Alternatives:")
        print("1. Use Docker container: coiled.create_software_environment(container='...')")
        print("2. Continue with runtime installation (current approach)")
        print("3. Upgrade Coiled package: pip install --upgrade coiled")
    else:
        raise

except Exception as e:
    print(f"❌ Error creating environment: {e}")
    raise
