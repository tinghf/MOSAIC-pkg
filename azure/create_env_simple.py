#!/usr/bin/env python
"""
Simple approach: Use include_local_code to bundle MOSAIC package code.
This won't install dependencies, but we can add those to conda environment.
"""

import coiled

print("Creating Coiled environment with local MOSAIC code...")

# This bundles your local MOSAIC-pkg code into the environment
# But won't install R package dependencies - those need to be in conda env
result = coiled.create_software_environment(
    name="mosaic-pkg-local",
    conda="azure/coiled_environment.yml",
    include_local_code=True,  # Includes local Python/R code
    region_name="westus2",
    force_rebuild=True
)

print("✅ Environment created with local code")
print()
print("⚠️  Note: This includes MOSAIC source code but not installed dependencies")
print("    Workers will still need to install R packages at runtime")
