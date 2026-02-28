#!/bin/bash
# Coiled post-build script to install MOSAIC R package on workers

set -e  # Exit on error

echo "======================================"
echo "Installing MOSAIC R package"
echo "======================================"

# Install MOSAIC from GitHub
Rscript -e "
options(repos = c(CRAN = 'https://cloud.r-project.org'))

cat('Installing MOSAIC R package from GitHub...\\n')
remotes::install_github(
  'InstituteforDiseaseModeling/MOSAIC-pkg',
  dependencies = TRUE,
  upgrade = 'never'
)

cat('Loading MOSAIC...\\n')
library(MOSAIC)

cat('Installing Python dependencies...\\n')
MOSAIC::install_dependencies(force = TRUE)

cat('Verifying installation...\\n')
MOSAIC::check_dependencies()

cat('✅ MOSAIC installation complete\\n')
"

echo "======================================"
echo "MOSAIC installation successful"
echo "======================================"
