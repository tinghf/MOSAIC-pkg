FROM rocker/geospatial:4.4

LABEL maintainer="MOSAIC Team"
LABEL description="MOSAIC (Metapopulation Outbreak Simulation with Agent-based Implementation for Cholera)"
LABEL version="0.13.24"

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Set environment variables for threading (critical for MOSAIC - see CLAUDE.md)
ENV OMP_NUM_THREADS=1
ENV MKL_NUM_THREADS=1
ENV NUMBA_NUM_THREADS=1
ENV TBB_NUM_THREADS=1
ENV KMP_DUPLICATE_LIB_OK=TRUE
ENV R_DATATABLE_NUM_THREADS=1

# ============================================================
# Install additional system dependencies
# ============================================================
# Note: rocker/geospatial already includes:
#   - R 4.4+, build-essential, gfortran, cmake
#   - GDAL, PROJ, GEOS, UDUNITS
#   - sf, terra, raster packages
#
# We only need to add MOSAIC-specific requirements:
#   - HDF5 (for LASER output files)
#   - Python 3.9+ (for LASER-cholera simulation engine)
#   - Additional graphics/font libraries
# ============================================================

RUN apt-get update && apt-get install -y --no-install-recommends \
    # HDF5 for reading LASER simulation outputs
    libhdf5-dev \
    zlib1g-dev \
    # Python 3.9+ (check version and install if needed)
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    software-properties-common \
    # Graphics and font libraries for R plotting
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    # Git for installing from GitHub
    git \
    ca-certificates \
    # Utilities
    wget \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# Ensure Python >= 3.9
# ============================================================
RUN PYTHON_VERSION=$(python3 --version 2>&1 | grep -oP '\d+\.\d+' | head -1) && \
    PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1) && \
    PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2) && \
    if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 9 ]); then \
        echo "Python $PYTHON_VERSION detected, installing Python 3.9..." && \
        add-apt-repository -y ppa:deadsnakes/ppa && \
        apt-get update && \
        apt-get install -y python3.9 python3.9-venv python3.9-dev && \
        update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.9 1 && \
        rm -rf /var/lib/apt/lists/*; \
    else \
        echo "Python $PYTHON_VERSION detected (OK)"; \
    fi

# ============================================================
# Install MOSAIC R package
# ============================================================
# Install from GitHub (change to local path if building from source)
RUN R -e "options(repos = c(CRAN = 'https://cloud.r-project.org')); \
    if (!requireNamespace('remotes', quietly = TRUE)) { \
        install.packages('remotes'); \
    }; \
    remotes::install_github('InstituteforDiseaseModeling/MOSAIC-pkg', \
        dependencies = TRUE, \
        upgrade = 'never', \
        force = TRUE)"

# Alternative: Install from local source (uncomment if building from repo)
# COPY . /tmp/MOSAIC-pkg
# RUN R CMD INSTALL /tmp/MOSAIC-pkg && rm -rf /tmp/MOSAIC-pkg

# ============================================================
# Install Python dependencies (LASER-cholera, PyTorch, NPE)
# ============================================================
# This creates a conda environment: ~/.virtualenvs/r-mosaic
# Key packages: laser-cholera==0.9.1, pytorch==2.1.2, sbi==0.22.0
RUN R -e "MOSAIC::install_dependencies(force = TRUE)"

# ============================================================
# Verify installation
# ============================================================
RUN R -e "library(MOSAIC); \
    result <- tryCatch({ \
        MOSAIC::check_dependencies(); \
        cat('✓ MOSAIC installation verified successfully\n'); \
        TRUE \
    }, error = function(e) { \
        cat('ERROR:', e\$message, '\n'); \
        FALSE \
    }); \
    if (!result) quit(status = 1)"

# ============================================================
# Setup working directory and default command
# ============================================================
WORKDIR /workspace

# Create directories for MOSAIC workflows
RUN mkdir -p /workspace/model/input && \
    mkdir -p /workspace/model/output && \
    mkdir -p /workspace/data

# Copy example workflow (optional - uncomment if you want to include it)
# COPY model/LAUNCH.R /workspace/model/LAUNCH.R

# Set default command to R console
CMD ["R"]

# ============================================================
# Usage instructions:
# ============================================================
# Build:
#   docker build -t mosaic:latest .
#
# Run interactive R session:
#   docker run -it --rm mosaic:latest
#
# Run with mounted data directory:
#   docker run -it --rm \
#     -v $(pwd)/model:/workspace/model \
#     -v $(pwd)/data:/workspace/data \
#     mosaic:latest
#
# Run a specific R script:
#   docker run --rm \
#     -v $(pwd)/model:/workspace/model \
#     mosaic:latest Rscript /workspace/model/LAUNCH.R
#
# Get a bash shell:
#   docker run -it --rm mosaic:latest bash
# ============================================================
