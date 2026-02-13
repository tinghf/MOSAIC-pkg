# MOSAIC Docker Guide

This guide explains how to build and run MOSAIC in a Docker container using the provided `Dockerfile`.

## Quick Start

### Build the Docker image

```bash
docker build -t mosaic:latest .
```

**Build time**: ~15-20 minutes (first build), ~2-3 minutes (subsequent builds with cache)

### Run interactive R session

```bash
docker run -it --rm mosaic:latest
```

### Run with your data mounted

```bash
docker run -it --rm \
  -v $(pwd)/model:/workspace/model \
  -v $(pwd)/data:/workspace/data \
  mosaic:latest
```

## Using Docker Compose

For easier management, use Docker Compose:

```bash
# Start container
docker-compose run --rm mosaic

# Or start in background
docker-compose up -d mosaic

# Attach to running container
docker exec -it mosaic-workspace R
```

## Common Usage Patterns

### 1. Interactive R Development

```bash
docker run -it --rm \
  -v $(pwd)/model:/workspace/model \
  -v $(pwd)/data:/workspace/data \
  mosaic:latest R
```

Then in R:
```r
library(MOSAIC)
check_dependencies()

# Run calibration
config <- get_location_config("Angola", "Luanda")
priors <- get_location_priors("Angola", "Luanda")
results <- run_MOSAIC(config, priors)
```

### 2. Run a Specific Script

```bash
docker run --rm \
  -v $(pwd)/model:/workspace/model \
  -v $(pwd)/data:/workspace/data \
  mosaic:latest Rscript /workspace/model/LAUNCH.R
```

### 3. Bash Shell Access

```bash
docker run -it --rm \
  -v $(pwd)/model:/workspace/model \
  mosaic:latest bash
```

### 4. Parallel Processing with Limited CPUs

```bash
docker run --rm \
  --cpus=4 \
  --memory=8g \
  -v $(pwd)/model:/workspace/model \
  mosaic:latest Rscript my_script.R
```

### 5. Jupyter Notebook (if needed)

```bash
docker run -it --rm \
  -p 8888:8888 \
  -v $(pwd)/model:/workspace/model \
  mosaic:latest \
  bash -c "pip install jupyter && jupyter notebook --ip=0.0.0.0 --allow-root"
```

## Image Details

### Base Image
- **Base**: `rocker/geospatial:4.4`
- **R version**: 4.4+
- **Python version**: 3.9+
- **Pre-installed geospatial**: sf, terra, raster, GDAL, PROJ, GEOS

### Included Software
- **MOSAIC R package**: Latest from GitHub
- **LASER-cholera**: 0.9.1 (Python simulation engine)
- **PyTorch**: 2.1.2 (for NPE)
- **SBI ecosystem**: sbi, lampe, zuko (normalizing flows)

### Environment Variables

The following threading limits are set by default (critical for stability):
```
OMP_NUM_THREADS=1
MKL_NUM_THREADS=1
NUMBA_NUM_THREADS=1
TBB_NUM_THREADS=1
KMP_DUPLICATE_LIB_OK=TRUE
R_DATATABLE_NUM_THREADS=1
```

See [CLAUDE.md](CLAUDE.md) for details on why these are necessary.

## Directory Structure

Inside the container:
```
/workspace/
├── model/           # Mount your MOSAIC model directory here
│   ├── input/       # LASER input files
│   ├── output/      # Calibration results
│   └── LAUNCH.R     # Your workflow script
└── data/            # Mount your data directory here
```

## Troubleshooting

### Build fails with "unable to access GitHub"

If you're behind a corporate firewall:
```bash
docker build --build-arg HTTP_PROXY=http://your-proxy:port \
             --build-arg HTTPS_PROXY=http://your-proxy:port \
             -t mosaic:latest .
```

### Python dependencies fail to install

The `MOSAIC::install_dependencies()` step creates a conda environment and can take 10-15 minutes. If it fails:

1. Check available disk space (need ~5GB for conda)
2. Increase Docker's memory allocation (need at least 4GB)
3. Check the build logs: `docker build --no-cache -t mosaic:latest .`

### Container runs out of memory

MOSAIC calibration can be memory-intensive. Increase Docker's memory:

**Docker Desktop**: Settings → Resources → Memory → Set to 16GB

**Command line**:
```bash
docker run --memory=16g --rm -it mosaic:latest
```

### Permission errors with mounted volumes

If you get permission errors accessing mounted directories:

**Linux/Mac**:
```bash
docker run --rm -it \
  --user $(id -u):$(id -g) \
  -v $(pwd)/model:/workspace/model \
  mosaic:latest
```

**Windows** (PowerShell):
```powershell
docker run --rm -it `
  -v ${PWD}/model:/workspace/model `
  mosaic:latest
```

## Building from Local Source

If you've made local changes to MOSAIC and want to build from your modified code:

1. Edit `Dockerfile` and uncomment these lines:
   ```dockerfile
   # COPY . /tmp/MOSAIC-pkg
   # RUN R CMD INSTALL /tmp/MOSAIC-pkg && rm -rf /tmp/MOSAIC-pkg
   ```

2. Comment out the GitHub install line:
   ```dockerfile
   # RUN R -e "remotes::install_github(...)"
   ```

3. Build:
   ```bash
   docker build -t mosaic:dev .
   ```

## Performance Tuning

### Multi-core Calibration

MOSAIC uses R's `parallel` package. Control cores with:

```r
control <- list(
  parallel = list(
    enable = TRUE,
    n_cores = 4  # Adjust based on your Docker CPU limits
  )
)

results <- run_MOSAIC(config, priors, control = control)
```

### GPU Support (for NPE)

If you have NVIDIA GPUs and want to accelerate NPE training:

1. Install [nvidia-docker](https://github.com/NVIDIA/nvidia-docker)
2. Run with GPU access:
   ```bash
   docker run --gpus all --rm -it \
     -v $(pwd)/model:/workspace/model \
     mosaic:latest
   ```

3. PyTorch will automatically detect and use GPUs

## Saving Results

Results are saved to `/workspace/model/output/` inside the container. To persist them:

**Option 1**: Mount the entire model directory (recommended)
```bash
-v $(pwd)/model:/workspace/model
```

**Option 2**: Copy results out after run
```bash
docker cp mosaic-workspace:/workspace/model/output ./results/
```

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Run MOSAIC Calibration
on: [push]
jobs:
  calibrate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build Docker image
        run: docker build -t mosaic:ci .
      - name: Run calibration
        run: |
          docker run --rm \
            -v ${{ github.workspace }}/model:/workspace/model \
            mosaic:ci Rscript /workspace/model/LAUNCH.R
      - name: Upload results
        uses: actions/upload-artifact@v3
        with:
          name: calibration-results
          path: model/output/
```

## Additional Resources

- **MOSAIC Documentation**: https://institutefordiseasemodeling.github.io/MOSAIC-docs/
- **Package Reference**: https://institutefordiseasemodeling.github.io/MOSAIC-pkg/
- **Rocker Project**: https://rocker-project.org/
- **Issues**: https://github.com/InstituteforDiseaseModeling/MOSAIC-pkg/issues

## Security Notes

- The container runs as `root` by default (inherited from rocker/geospatial)
- For production use, consider creating a non-root user
- Don't mount sensitive credentials as volumes
- Use Docker secrets for API keys if needed

## Clean Up

Remove containers and images:
```bash
# Remove stopped containers
docker container prune

# Remove the image
docker rmi mosaic:latest

# Remove all unused images, containers, volumes
docker system prune -a
```
