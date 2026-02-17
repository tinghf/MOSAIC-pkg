# MOSAIC Container Deployment Guide

## Overview

This guide shows how to deploy MOSAIC on SLURM clusters using Singularity/Apptainer containers instead of direct installation. This approach provides:

✅ **No cluster setup required** - Build once, run anywhere
✅ **Reproducibility** - Same environment across all nodes
✅ **Version control** - Pin exact dependency versions
✅ **Easy updates** - Just rebuild and replace container
✅ **Clean filesystem** - No conda/R packages cluttering home directory

## Prerequisites

- **Local machine** with Docker/Singularity for building (or use cluster build node)
- **SLURM cluster** with Singularity or Apptainer installed
- **Shared filesystem** between login and compute nodes (e.g., `/home`, `/scratch`)

## Quick Start

### Option 1: Build Container Locally (Recommended)

```bash
# On your local machine (with sudo access)
cd /path/to/MOSAIC
git clone https://github.com/InstituteforDiseaseModeling/MOSAIC-pkg.git
cd ..

# Build container (takes 20-40 minutes)
sudo singularity build mosaic_latest.sif MOSAIC-pkg/inst/containers/mosaic.def

# Transfer to cluster
scp mosaic_latest.sif your-username@cluster.edu:~/containers/
```

### Option 2: Build on Cluster

```bash
# SSH to cluster
ssh your-username@cluster.edu

# Clone repo (only needed for building, can delete after)
git clone https://github.com/InstituteforDiseaseModeling/MOSAIC-pkg.git
cd ..

# Build container (may require special permissions or build node)
singularity build --fakeroot mosaic_latest.sif MOSAIC-pkg/inst/containers/mosaic.def

# Move to persistent location
mkdir -p ~/containers
mv mosaic_latest.sif ~/containers/

# Clean up source (no longer needed!)
rm -rf MOSAIC-pkg
```

### Option 3: Use Pre-Built Container

```bash
# If your team maintains a shared container registry:
singularity pull ~/containers/mosaic_latest.sif docker://your-registry/mosaic:latest
```

## Usage

### Test Container

```bash
# Interactive R session
singularity exec ~/containers/mosaic_latest.sif R

# Run R script
singularity exec ~/containers/mosaic_latest.sif Rscript my_analysis.R

# Check MOSAIC installation
singularity exec ~/containers/mosaic_latest.sif Rscript -e "library(MOSAIC); check_dependencies()"
```

### Configure MOSAIC for Container

Create your R script (`run_mosaic_container.R`):

```r
#!/usr/bin/env Rscript
library(MOSAIC)

# Your analysis configuration
iso_codes <- c("ETH", "KEN", "SOM")
config <- get_location_config(iso = iso_codes)
priors <- get_location_priors(iso = iso_codes)

# Configure for SLURM with CONTAINER template
control <- mosaic_control_defaults(
  calibration = list(
    n_simulations = 10000,
    n_iterations = 3
  ),
  parallel = list(
    enable = TRUE,
    type = "future",
    n_cores = 100,
    backend = "slurm",

    # KEY: Use container template
    template = system.file("templates/slurm-container.tmpl", package = "MOSAIC"),

    resources = list(
      cpus = 1,
      memory = "6GB",
      walltime = "04:00:00",
      partition = "compute",

      # IMPORTANT: Specify container path
      container_image = "~/containers/mosaic_latest.sif"
    )
  )
)

# Run (submits jobs using container)
results <- run_MOSAIC(config, priors, "./output", control = control)
```

### Run on SLURM

```bash
# Submit from login node (MOSAIC must be available on login node)
# Option A: Use container on login node too
singularity exec ~/containers/mosaic_latest.sif Rscript run_mosaic_container.R

# Option B: Use locally installed MOSAIC (only workers use container)
Rscript run_mosaic_container.R
```

## Deployment Strategies

### Strategy 1: Container Everywhere (Cleanest)

**What**: Use container on both login node and compute nodes
**Pros**: Perfectly reproducible, no local installation
**Cons**: Slightly more verbose commands

```bash
# All commands use container
singularity exec ~/containers/mosaic_latest.sif R
singularity exec ~/containers/mosaic_latest.sif Rscript analysis.R
```

### Strategy 2: Hybrid (Most Practical)

**What**: Install MOSAIC on login node, use container on compute nodes
**Pros**: Convenient interactive development, reproducible production
**Cons**: Two installations to maintain

```bash
# Login node: Regular installation
bash vm/setup_mosaic.sh

# Compute nodes: Use container (automatically via SLURM template)
# Just set: resources = list(container_image = "~/containers/mosaic_latest.sif")
```

### Strategy 3: Shared Container Location

**What**: Team shares single container on shared filesystem
**Pros**: One container for entire group, easy updates
**Cons**: Requires coordination on versions

```bash
# System admin places container in shared location
/projects/cholera/containers/mosaic_v0.14.0.sif

# All users reference same container
control$parallel$resources$container_image <- "/projects/cholera/containers/mosaic_v0.14.0.sif"
```

## Customizing the Container

### Modify Dependencies

Edit [`inst/containers/mosaic.def`](../inst/containers/mosaic.def):

```singularity
%post
    # Add custom R packages
    Rscript -e "install.packages('ggplot2', repos='https://cloud.r-project.org')"

    # Add custom Python packages
    conda activate mosaic-conda-env
    pip install pandas scikit-learn

    # Add system tools
    apt-get install -y vim htop
```

Then rebuild:
```bash
sudo singularity build mosaic_custom.sif inst/containers/mosaic.def
```

### Add Custom Data

```singularity
%files
    ./my_data /opt/data
    ./my_scripts /opt/scripts

%environment
    export MOSAIC_DATA_PATH=/opt/data
```

### Pin Specific Version

```singularity
%post
    # Checkout specific MOSAIC version
    cd /opt/MOSAIC-pkg
    git checkout v0.13.24
    R CMD INSTALL .
```

## Troubleshooting

### Container Build Fails

**Issue**: Permission denied during build

```bash
# Try with --fakeroot (no sudo needed)
singularity build --fakeroot mosaic.sif mosaic.def

# Or use sandbox mode for debugging
sudo singularity build --sandbox mosaic/ mosaic.def
sudo singularity exec --writable mosaic/ bash  # Debug inside
sudo singularity build mosaic.sif mosaic/
```

**Issue**: R packages fail to install

```singularity
%post
    # Add retries and better error messages
    Rscript -e "options(repos='https://cloud.r-project.org'); install.packages('arrow')" || \
        (echo "ERROR: Failed to install arrow" && exit 1)
```

### Container Too Large

```singularity
%post
    # Clean up after installs
    conda clean -afy
    apt-get clean
    rm -rf /var/lib/apt/lists/*
    rm -rf /tmp/*
    rm -rf ~/.cache

    # Remove development files (if not needed)
    apt-get remove -y build-essential
```

**Typical sizes**:
- Minimal MOSAIC: ~2-3 GB
- With all dependencies: ~4-5 GB
- With dev tools: ~6-8 GB

### Jobs Fail with "Permission Denied"

**Issue**: Container can't write to output directory

```bash
# Check bind mounts in slurm-container.tmpl
BIND_MOUNTS="<%= getwd() %>:<%= getwd() %>"

# Add write directories
BIND_MOUNTS="${BIND_MOUNTS},/scratch/${USER}:/scratch/${USER}"
```

**Issue**: Home directory not accessible

```bash
# Most clusters auto-bind /home, but if not:
singularity exec --bind /home:/home ...
```

### Module Not Found Errors

**Issue**: Python packages not found inside container

```bash
# Verify container environment
singularity exec mosaic.sif python -c "import laser_cholera; print('OK')"

# Check conda activation in container
singularity exec mosaic.sif bash -c "source /opt/conda/etc/profile.d/conda.sh && conda activate mosaic-conda-env && python -c 'import laser_cholera'"
```

**Fix**: Ensure `%environment` section in `.def` file activates conda correctly.

## Performance Considerations

### Container Overhead

- **Negligible**: Singularity adds <1% runtime overhead
- **Same performance**: MOSAIC runs at native speed in container
- **I/O bound**: Most time spent in Python/R computation, not containerization

### Caching

```bash
# Singularity caches layers - faster rebuilds
export SINGULARITY_CACHEDIR=~/singularity_cache
mkdir -p $SINGULARITY_CACHEDIR
```

### Parallel Performance

Container version performs identically to native installation:
- Same threading limits apply
- Same SLURM resource management
- Same multi-country scaling

## Version Management

### Semantic Versioning

```bash
# Build version-tagged containers
singularity build mosaic_v0.14.0.sif mosaic.def

# Symlink to "latest"
ln -sf mosaic_v0.14.0.sif ~/containers/mosaic_latest.sif

# Scripts always use "latest" symlink
resources$container_image <- "~/containers/mosaic_latest.sif"
```

### Team Workflow

```bash
# 1. Developer builds and tests new version
singularity build mosaic_v0.14.1.sif mosaic.def
singularity exec mosaic_v0.14.1.sif Rscript test_hpc_setup.R

# 2. Copy to shared location
cp mosaic_v0.14.1.sif /projects/cholera/containers/

# 3. Team updates symlinks when ready
ln -sf /projects/cholera/containers/mosaic_v0.14.1.sif ~/containers/mosaic_latest.sif
```

## Comparison: Container vs Direct Install

| Aspect | Container | Direct Install |
|--------|-----------|---------------|
| Initial setup time | 30-60 min (build) | 30-60 min (install) |
| Deployment time | <1 min (copy file) | 30-60 min (every node) |
| Reproducibility | ✅ Perfect | ⚠️ Varies by node |
| Updates | Copy new container | Re-run setup script |
| Storage | ~4-5 GB per container | ~2-3 GB in home dir |
| Portability | ✅ Works on any cluster | ❌ Cluster-specific |
| Debugging | ⚠️ Requires rebuild | ✅ Edit files directly |
| Team coordination | ✅ Share one file | ⚠️ Each person installs |

## Recommended Workflow

**For individual researchers**:
1. Build container locally (or use team container)
2. Copy to cluster
3. Use hybrid strategy (local install for dev, container for production)

**For research groups**:
1. CI/CD pipeline builds containers on GitHub
2. Containers stored in shared cluster location
3. Version pinning for reproducibility
4. All jobs use container template

**For publications**:
1. Archive exact container used for paper
2. Deposit on Zenodo/Figshare
3. Document version in methods section
4. Enables perfect reproducibility

## Next Steps

1. **Build container**: Follow Quick Start instructions
2. **Test locally**: `singularity exec mosaic.sif R`
3. **Test on cluster**: Update `run_mosaic_container.R` with your paths
4. **Run production**: Use container template for all calibrations

## Resources

- Container definition: [`inst/containers/mosaic.def`](../inst/containers/mosaic.def)
- SLURM template: [`inst/templates/slurm-container.tmpl`](../inst/templates/slurm-container.tmpl)
- Singularity docs: https://docs.sylabs.io/guides/latest/user-guide/
- Apptainer docs: https://apptainer.org/docs/user/latest/
