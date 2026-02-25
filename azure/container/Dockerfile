# ==============================================================================
# MOSAIC Container Image
# ==============================================================================
# Multi-stage build for optimized container size
#
# Build:
#   docker build -t mosaic:latest -f azure/container/Dockerfile .
#
# Run locally:
#   docker run --rm -e ISO_CODE=SOM -v $(pwd)/outputs:/outputs mosaic:latest
#
# ==============================================================================

FROM ubuntu:20.04 AS builder

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install system dependencies (matches vm/setup_mosaic.sh)
RUN apt-get update && apt-get install -y \
    git \
    ca-certificates \
    build-essential \
    gfortran \
    cmake \
    software-properties-common \
    dirmngr \
    wget \
    curl \
    # R dependencies
    r-base \
    r-base-dev \
    # Geospatial libraries
    gdal-bin libgdal-dev \
    libproj-dev proj-bin \
    libgeos-dev libgeos++-dev \
    libudunits2-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    libhdf5-dev \
    zlib1g-dev \
    # Python
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
  && rm -rf /var/lib/apt/lists/*

# Install R 4.1+ from CRAN
RUN wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc \
  && add-apt-repository "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/" \
  && apt-get update \
  && apt-get install -y r-base r-base-dev \
  && rm -rf /var/lib/apt/lists/*

# Set R library path
RUN mkdir -p /usr/local/lib/R/site-library
ENV R_LIBS_USER=/usr/local/lib/R/site-library

# Install remotes first
RUN Rscript -e "install.packages('remotes', repos='https://cloud.r-project.org')"

# Install geospatial packages (version-pinned for Ubuntu 20.04)
RUN Rscript -e " \
  options(repos = c(CRAN = 'https://cloud.r-project.org')); \
  install.packages('sf', configure.args = '--with-proj-lib=/usr/lib'); \
  remotes::install_version('terra', version = '1.7.71'); \
  remotes::install_version('raster', version = '3.6.26'); \
"

# Copy MOSAIC source code
WORKDIR /tmp/MOSAIC-pkg
COPY . .

# Install MOSAIC R package
RUN Rscript -e " \
  options(repos = c(CRAN = 'https://cloud.r-project.org')); \
  remotes::install_local('.', dependencies = TRUE, upgrade = 'never'); \
"

# Install Python dependencies
RUN Rscript -e "MOSAIC::install_dependencies(force = TRUE)"

# ==============================================================================
# Runtime stage (smaller final image)
# ==============================================================================
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install only runtime dependencies
RUN apt-get update && apt-get install -y \
    r-base \
    python3 \
    python3-pip \
    libgdal-dev \
    libproj-dev \
    libgeos-dev \
    libudunits2-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libhdf5-dev \
  && rm -rf /var/lib/apt/lists/*

# Copy R libraries from builder
COPY --from=builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library

# Copy Python environment from builder
COPY --from=builder /root/.virtualenvs /root/.virtualenvs
COPY --from=builder /root/.local/share/r-miniconda /root/.local/share/r-miniconda

# Copy MOSAIC package
COPY --from=builder /tmp/MOSAIC-pkg /opt/MOSAIC-pkg

# Set environment variables
ENV R_LIBS_USER=/usr/local/lib/R/site-library
ENV MOSAIC_ROOT=/opt/MOSAIC-pkg
ENV RETICULATE_PYTHON=/root/.virtualenvs/r-mosaic/bin/python

# Create output directory
RUN mkdir -p /outputs

# Copy entrypoint script
COPY azure/container/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /opt/MOSAIC-pkg

# Default command
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["SOM"]
