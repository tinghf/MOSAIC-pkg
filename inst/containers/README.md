# MOSAIC Container Deployment

**Quick containerized deployment for HPC clusters - no installation required!**

## TL;DR

```bash
# 1. Build container (on your laptop)
cd /path/to/MOSAIC-pkg/..
sudo singularity build mosaic_latest.sif MOSAIC-pkg/inst/containers/mosaic.def

# 2. Copy to cluster
scp mosaic_latest.sif username@cluster.edu:~/containers/

# 3. Run on cluster
ssh username@cluster.edu
singularity exec ~/containers/mosaic_latest.sif Rscript examples/run_mosaic_container.R
```

**Done!** No conda, no R packages, no setup scripts on cluster.

---

## Why Containers?

| Traditional | Container |
|------------|-----------|
| 30-60 min setup per cluster | Copy 1 file |
| Environment varies by node | Identical everywhere |
| Conda/R libs in home dir | Clean filesystem |
| Update = re-run setup | Update = copy new file |

---

## Files in This Directory

```
inst/containers/
├── README.md                    # This file
├── mosaic.def                   # Singularity definition file
└── build_and_deploy.sh          # Automated build/deploy script
```

---

## Quick Start (Automated)

```bash
# Interactive mode
bash inst/containers/build_and_deploy.sh

# Or one-liner
bash inst/containers/build_and_deploy.sh all username@cluster.edu
```

---

## Manual Build & Deploy

### Build Locally

```bash
# On laptop/workstation with Singularity
cd /path/to/MOSAIC-pkg/..
sudo singularity build mosaic_latest.sif MOSAIC-pkg/inst/containers/mosaic.def
```

**Time**: 30-40 minutes
**Size**: ~4-5 GB
**Requires**: Singularity/Apptainer + sudo

### Deploy to Cluster

```bash
# Copy container
scp mosaic_latest.sif username@cluster.edu:~/containers/

# Test
ssh username@cluster.edu
singularity exec ~/containers/mosaic_latest.sif R
```

---

## Usage on Cluster

### Interactive R Session

```bash
singularity exec ~/containers/mosaic_latest.sif R
```

```r
library(MOSAIC)
check_dependencies()  # Should all pass
```

### Run MOSAIC Script

```r
# In your R script: examples/run_mosaic_container.R
control <- mosaic_control_defaults(
  parallel = list(
    type = "future",
    backend = "slurm",
    template = system.file("templates/slurm-container.tmpl", package = "MOSAIC"),
    resources = list(
      container_image = "~/containers/mosaic_latest.sif"  # ← KEY
    )
  )
)
```

### Submit to SLURM

```bash
# If MOSAIC installed on login node:
Rscript examples/run_mosaic_container.R

# Or use container everywhere:
singularity exec ~/containers/mosaic_latest.sif Rscript examples/run_mosaic_container.R
```

---

## Templates

Two SLURM templates available:

1. **Standard** ([inst/templates/slurm.tmpl](../templates/slurm.tmpl))
   For traditional cluster installation

2. **Container** ([inst/templates/slurm-container.tmpl](../templates/slurm-container.tmpl))
   For containerized deployment (use this one!)

---

## Customization

### Pin Specific Version

Edit `mosaic.def`:
```singularity
%post
    cd /opt/MOSAIC-pkg
    git checkout v0.13.24  # ← Specific version
    R CMD INSTALL .
```

### Add Custom Packages

```singularity
%post
    # R packages
    Rscript -e "install.packages('tidyverse')"

    # Python packages
    conda activate mosaic-conda-env
    pip install scikit-learn
```

### Reduce Size

```singularity
%post
    # Remove development tools
    apt-get remove -y build-essential
    apt-get autoremove -y

    # Aggressive cleaning
    conda clean -afy
    rm -rf /tmp/* ~/.cache
```

---

## Troubleshooting

### "Permission denied" during build

```bash
# Use --fakeroot (no sudo needed)
singularity build --fakeroot mosaic_latest.sif mosaic.def
```

### Container too large to transfer

```bash
# Compress before transfer
gzip mosaic_latest.sif  # → mosaic_latest.sif.gz (saves ~30%)
scp mosaic_latest.sif.gz username@cluster.edu:~/containers/
ssh username@cluster.edu "gunzip ~/containers/mosaic_latest.sif.gz"
```

### Jobs fail with "container not found"

```r
# Use absolute path
control$parallel$resources$container_image <- "/home/username/containers/mosaic_latest.sif"

# Or ensure home directory is auto-bound by Singularity
```

### Python modules not found

```bash
# Test conda environment activation
singularity exec mosaic_latest.sif bash -c "
  source /opt/conda/etc/profile.d/conda.sh
  conda activate mosaic-conda-env
  python -c 'import laser_cholera; print(\"OK\")'
"
```

---

## Advanced Usage

### Shared Team Container

```bash
# Admin deploys to shared location
cp mosaic_latest.sif /projects/cholera/containers/mosaic_v0.14.0.sif

# Users reference shared container
control$parallel$resources$container_image <- "/projects/cholera/containers/mosaic_v0.14.0.sif"
```

### Version Control

```bash
# Build with version tags
singularity build mosaic_v0.14.0.sif mosaic.def

# Symlink to latest
ln -sf mosaic_v0.14.0.sif ~/containers/mosaic_latest.sif

# Scripts always use "latest"
resources$container_image <- "~/containers/mosaic_latest.sif"
```

### CI/CD Pipeline

```yaml
# .github/workflows/build-container.yml
name: Build Container
on: [push, release]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build container
        run: |
          sudo apt-get install -y singularity-container
          singularity build mosaic_${GITHUB_REF_NAME}.sif inst/containers/mosaic.def
      - name: Upload artifact
        uses: actions/upload-artifact@v3
        with:
          name: mosaic-container
          path: mosaic_*.sif
```

---

## Resources

- **Full Guide**: [docs/CONTAINER_DEPLOYMENT.md](../../docs/CONTAINER_DEPLOYMENT.md)
- **Example Script**: [examples/run_mosaic_container.R](../../examples/run_mosaic_container.R)
- **SLURM Guide**: [docs/SLURM_DEPLOYMENT.md](../../docs/SLURM_DEPLOYMENT.md)
- **Singularity Docs**: https://docs.sylabs.io/guides/latest/user-guide/

---

## Support

- **Issues**: https://github.com/InstituteforDiseaseModeling/MOSAIC-pkg/issues
- **Discussions**: https://github.com/InstituteforDiseaseModeling/MOSAIC-pkg/discussions
- **Documentation**: https://institutefordiseasemodeling.github.io/MOSAIC-docs/

---

**Built by**: Institute for Disease Modeling
**License**: MIT
