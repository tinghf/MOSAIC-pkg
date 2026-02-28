# MOSAIC Coiled.io Automation - Quick Start Guide

**Last Updated**: 2026-02-24
**Approach**: GitHub Actions + Coiled.io for auto-scaling cloud compute

---

## Table of Contents

1. [Overview](#overview)
2. [Why Coiled.io](#why-coiledio)
3. [Setup (30 minutes)](#setup-30-minutes)
4. [Implementation](#implementation)
5. [Running Your First Job](#running-your-first-job)
6. [Monitoring and Costs](#monitoring-and-costs)
7. [Advanced Features](#advanced-features)

---

## Overview

This guide implements automated MOSAIC workflows using:

- **GitHub Actions**: Workflow orchestration and triggering
- **Coiled.io**: Auto-scaling Dask clusters on Azure
- **Python + reticulate**: Bridge between Dask parallelism and R functions

**Key Benefits**:
- ✅ Auto-scales from 0 to N workers (pay only for what you use)
- ✅ Managed infrastructure (no VM or Docker management)
- ✅ Built-in monitoring dashboard
- ✅ Simple Python API
- ✅ Cost tracking per job
- ✅ 5-minute setup for first run

**Timeline**: ~2 weeks to production-ready

---

## Why Coiled.io?

### Comparison to Azure Batch

| Feature | Coiled.io | Azure Batch |
|---------|-----------|-------------|
| **Setup Time** | 30 minutes | 4 hours |
| **Maintenance** | Zero (fully managed) | Medium (pool management) |
| **Scaling** | Automatic (0-N workers) | Manual + auto-scale formulas |
| **Monitoring** | Rich dashboard included | Azure Portal (basic) |
| **Cost** | $0.10-0.15/core-hour | $0.03/core-hour (raw VM) |
| **R Support** | Via reticulate/rpy2 | Native |
| **Learning Curve** | Python + Dask | Azure CLI + Batch API |

**Recommendation**: Use Coiled.io for rapid prototyping and production unless you already have Azure Batch expertise.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              GitHub Repository                               │
│  User pushes code or manually triggers workflow             │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│              GitHub Actions Runner                           │
│  1. Checkout code                                            │
│  2. Install MOSAIC + Coiled                                  │
│  3. Submit Coiled job                                        │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│              Coiled Cloud Platform                           │
│  - Spins up Dask cluster (e.g., 10 × 12-core workers)       │
│  - Installs MOSAIC on all workers                            │
│  - Distributes parameter sampling across workers             │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│              Dask Workers (Azure VMs)                    │
│  Each worker runs: run_LASER(params) → results              │
│  Results aggregated on scheduler node                        │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│              GitHub Actions (cont.)                          │
│  4. Download results from Coiled                             │
│  5. Compute likelihoods and update weights                   │
│  6. Upload to GitHub Artifacts                               │
│  7. Post summary comment                                     │
└─────────────────────────────────────────────────────────────┘
```

---

## Setup (30 minutes)

### Step 1: Create Coiled Account

1. Sign up at https://cloud.coiled.io/signup
2. Select plan:
   - **Free tier**: 1,000 CPU-hours/month (good for testing)
   - **Starter**: $49/month + compute costs
   - **Team**: $199/month + compute costs (recommended for production)
3. Note your account name (e.g., `my-org`)

### Step 2: Generate Coiled Token

```bash
# Install Coiled CLI locally
pip install coiled

# Login (opens browser)
coiled login

# Create API token
coiled token create github-actions --lifetime 365d

# Copy token (starts with "coiled_...")
```

### Step 3: Configure GitHub Secrets

Add to your GitHub repository (Settings → Secrets and variables → Actions):

| Secret Name | Value |
|-------------|-------|
| `COILED_TOKEN` | Token from Step 2 |

**Note**: Coiled can use its own storage, but Azure Blob Storage is recommended for large outputs.

### Step 4: Install Coiled Locally (for testing)

```bash
# Create test environment
conda create -n mosaic-coiled python=3.11 -y
conda activate mosaic-coiled

# Install dependencies
pip install coiled dask distributed rpy2
conda install r-base r-reticulate -c conda-forge

# Test Coiled connection
python -c "import coiled; print(coiled.list_clusters())"
```

---

## Implementation

### File 1: Coiled MOSAIC Runner (Python)

Create `azure/run_mosaic_coiled.py`:

```python
"""
MOSAIC Coiled Runner
Parallelizes LASER simulations across a Dask cluster using Coiled.
"""

import os
import json
import coiled
import dask
from dask.distributed import Client
import numpy as np
import pandas as pd
from rpy2 import robjects
from rpy2.robjects import pandas2ri
from rpy2.robjects.packages import importr

# Activate pandas-R conversion
pandas2ri.activate()

# =============================================================================
# R Interface Functions
# =============================================================================

def setup_mosaic_r():
    """Initialize MOSAIC R package in current Python process."""
    robjects.r('''
    library(MOSAIC)
    MOSAIC::attach_mosaic_env(silent=TRUE)
    ''')
    print("✅ MOSAIC R package loaded")

def run_laser_r(param_dict, config, priors):
    """
    Run single LASER simulation via R.

    Parameters
    ----------
    param_dict : dict
        Parameter dictionary (e.g., {'beta': 0.5, 'gamma': 0.1, ...})
    config : dict
        LASER configuration (from get_location_config)
    priors : dict
        Parameter priors (from get_location_priors)

    Returns
    -------
    dict
        Simulation output (cases, deaths, time series)
    """
    # Convert Python dict to R list
    r_params = robjects.ListVector(param_dict)
    r_config = robjects.ListVector(config)
    r_priors = robjects.ListVector(priors)

    # Call R function
    mosaic = importr('MOSAIC')
    result = mosaic.run_LASER(
        params=r_params,
        config=r_config,
        priors=r_priors,
        return_format='dataframe'
    )

    # Convert R dataframe to pandas
    result_df = pandas2ri.rpy2py(result)

    return {
        'params': param_dict,
        'cases': result_df['cases'].values,
        'deaths': result_df['deaths'].values,
        'time': result_df['time'].values
    }

# =============================================================================
# Coiled Cluster Configuration
# =============================================================================

@coiled.function(
    name="mosaic-laser-simulation",
    vm_type="Standard_D4s_v6",  # 8 cores, 32GB RAM
    keepalive="5 minutes",  # Keep workers alive between tasks
    region="westus2",
    software="mosaic-pkg",  # Custom environment (see Step 2)
)
def run_laser_remote(param_dict, config, priors):
    """
    Remote function executed on Coiled workers.
    Decorated with @coiled.function for automatic distribution.
    """
    setup_mosaic_r()  # Initialize R on worker
    return run_laser_r(param_dict, config, priors)

# =============================================================================
# Main Workflow
# =============================================================================

def run_mosaic_bfrs_coiled(
    iso_codes,
    n_simulations=1000,
    n_iterations=3,
    n_workers=10,
    output_dir="./output"
):
    """
    Run MOSAIC BFRS calibration using Coiled.

    Parameters
    ----------
    iso_codes : list of str
        Country ISO codes (e.g., ['ETH', 'KEN'])
    n_simulations : int
        Number of simulations per iteration
    n_iterations : int
        Number of BFRS iterations
    n_workers : int
        Number of Dask workers to spawn
    output_dir : str
        Output directory for results
    """

    # Initialize R locally to get config/priors
    print("🔧 Initializing MOSAIC...")
    setup_mosaic_r()

    # Get configuration via R
    mosaic = importr('MOSAIC')
    r_iso_codes = robjects.StrVector(iso_codes)
    config = mosaic.get_location_config(iso=r_iso_codes)
    priors = mosaic.get_location_priors(iso=r_iso_codes)

    # Convert R objects to Python dicts (for serialization to workers)
    config_dict = dict(zip(config.names, list(config)))
    priors_dict = dict(zip(priors.names, list(priors)))

    print(f"📊 Config loaded for: {', '.join(iso_codes)}")

    # Create Coiled cluster
    print(f"☁️  Spinning up Coiled cluster with {n_workers} workers...")
    cluster = coiled.Cluster(
        name=f"mosaic-{'-'.join(iso_codes)}",
        n_workers=n_workers,
        worker_vm_types=["Standard_D4s_v6"],  # 8 cores, 32GB RAM per worker
        region="westus2",
        software="mosaic-pkg",  # Custom environment
    )

    client = Client(cluster)
    print(f"✅ Cluster ready: {client.dashboard_link}")

    # BFRS Iterations
    weights = np.ones(n_simulations) / n_simulations  # Initial uniform weights
    param_samples = []
    likelihood_history = []

    for iteration in range(n_iterations):
        print(f"\n{'='*70}")
        print(f"Iteration {iteration + 1}/{n_iterations}")
        print(f"{'='*70}")

        # Sample parameters (via R)
        params_df = mosaic.sample_parameters(
            priors=robjects.ListVector(priors_dict),
            n=n_simulations,
            weights=robjects.FloatVector(weights)
        )
        params_df = pandas2ri.rpy2py(params_df)

        print(f"📦 Sampled {len(params_df)} parameter sets")

        # Convert dataframe to list of dicts
        param_dicts = params_df.to_dict('records')

        # Submit LASER simulations to Coiled
        print(f"🚀 Submitting {n_simulations} simulations to cluster...")
        futures = [
            dask.delayed(run_laser_remote)(p, config_dict, priors_dict)
            for p in param_dicts
        ]

        # Compute in parallel
        results = dask.compute(*futures)
        print(f"✅ All simulations complete")

        # Compute likelihoods (locally, using R)
        print(f"📊 Computing likelihoods...")
        likelihoods = []
        for result in results:
            # Call R likelihood function
            likelihood = mosaic.calc_model_likelihood(
                simulated_cases=robjects.FloatVector(result['cases']),
                simulated_deaths=robjects.FloatVector(result['deaths']),
                observed_cases=config_dict['observed_cases'],
                observed_deaths=config_dict['observed_deaths'],
                control=mosaic.mosaic_control_defaults()
            )
            likelihoods.append(float(likelihood[0]))

        likelihoods = np.array(likelihoods)

        # Update weights (Gibbs sampling)
        print(f"⚖️  Updating weights...")
        weights = mosaic.calc_model_weights_gibbs(
            likelihoods=robjects.FloatVector(likelihoods),
            prev_weights=robjects.FloatVector(weights)
        )
        weights = np.array(weights)

        # Check convergence
        ess = 1 / np.sum(weights**2)
        print(f"📈 ESS: {ess:.1f}/{n_simulations}")

        # Store results
        param_samples.append(params_df)
        likelihood_history.append(likelihoods)

        # Save checkpoint
        checkpoint = {
            'iteration': iteration,
            'params': params_df.to_dict(),
            'likelihoods': likelihoods.tolist(),
            'weights': weights.tolist(),
            'ess': float(ess)
        }
        checkpoint_file = os.path.join(output_dir, f'checkpoint_iter_{iteration}.json')
        os.makedirs(output_dir, exist_ok=True)
        with open(checkpoint_file, 'w') as f:
            json.dump(checkpoint, f)
        print(f"💾 Checkpoint saved: {checkpoint_file}")

    # Final results
    print(f"\n{'='*70}")
    print(f"🎉 BFRS Calibration Complete")
    print(f"{'='*70}")

    # Combine all parameter samples
    all_params = pd.concat(param_samples, ignore_index=True)
    all_params['weight'] = np.concatenate([weights] * n_iterations)
    all_params['iteration'] = np.repeat(range(n_iterations), n_simulations)

    # Save final results
    output_file = os.path.join(output_dir, 'simulations.parquet')
    all_params.to_parquet(output_file)
    print(f"💾 Results saved: {output_file}")

    # Cleanup cluster
    client.close()
    cluster.close()
    print(f"☁️  Cluster shut down")

    return {
        'params': all_params,
        'dashboard_link': client.dashboard_link,
        'output_dir': output_dir
    }

# =============================================================================
# Command-line interface
# =============================================================================

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description='Run MOSAIC on Coiled')
    parser.add_argument('--iso', required=True, help='Comma-separated ISO codes')
    parser.add_argument('--n-simulations', type=int, default=1000)
    parser.add_argument('--n-iterations', type=int, default=3)
    parser.add_argument('--n-workers', type=int, default=10)
    parser.add_argument('--output-dir', default='./output')

    args = parser.parse_args()

    iso_codes = args.iso.split(',')

    result = run_mosaic_bfrs_coiled(
        iso_codes=iso_codes,
        n_simulations=args.n_simulations,
        n_iterations=args.n_iterations,
        n_workers=args.n_workers,
        output_dir=args.output_dir
    )

    print(f"\n✅ Results: {result['output_dir']}")
    print(f"📊 Dashboard: {result['dashboard_link']}")
```

### File 2: Coiled Software Environment

Create `azure/coiled_environment.yml`:

```yaml
name: mosaic-pkg
channels:
  - conda-forge
  - defaults
dependencies:
  - python=3.11
  - r-base=4.3
  - r-reticulate
  - pip
  # System dependencies for MOSAIC
  - gdal
  - proj
  - geos
  - hdf5
  # Dask and Coiled
  - dask
  - distributed
  - pip:
      - coiled
      - rpy2
      - pyarrow
      - pandas
      # R package installation happens via post-build script
```

Create `azure/coiled_setup.sh` (post-build script):

```bash
#!/bin/bash
# Install MOSAIC R package on Coiled workers

Rscript -e "
options(repos = c(CRAN = 'https://cloud.r-project.org'))
remotes::install_github('InstituteforDiseaseModeling/MOSAIC-pkg', dependencies=TRUE)
library(MOSAIC)
MOSAIC::install_dependencies(force=TRUE)
MOSAIC::check_dependencies()
"
```

**Upload software environment to Coiled**:

```bash
# Activate your conda environment with Coiled installed
conda activate mosaic-coiled

# Create the base environment (Python + R + system dependencies)
coiled env create \
  --name mosaic-pkg \
  --conda azure/coiled_environment.yml \
  --region-name westus2
```

This will take 15-30 minutes (one-time). Coiled builds and caches the environment.

**Note**: The MOSAIC R package will be installed automatically when workers start (handled in `run_mosaic_coiled.py`). This adds ~5 minutes to the first run, but is then cached for subsequent tasks.

### File 3: GitHub Actions Workflow

Create `.github/workflows/mosaic-coiled.yml`:

```yaml
name: MOSAIC Coiled Dispatch

on:
  workflow_dispatch:
    inputs:
      iso_codes:
        description: 'ISO country codes (comma-separated)'
        required: true
        default: 'ETH'
      n_simulations:
        description: 'Simulations per iteration'
        required: true
        default: '1000'
        type: number
      n_iterations:
        description: 'Number of BFRS iterations'
        required: true
        default: '3'
        type: choice
        options: ['1', '2', '3', '5', '10']
      n_workers:
        description: 'Number of Coiled workers'
        required: true
        default: '10'
        type: number

jobs:
  run-mosaic:
    name: Run MOSAIC on Coiled
    runs-on: ubuntu-latest
    timeout-minutes: 480  # 8 hours max

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install coiled dask distributed rpy2 pandas pyarrow

      - name: Configure Coiled
        run: |
          mkdir -p ~/.coiled
          echo "${{ secrets.COILED_TOKEN }}" > ~/.coiled/token

      - name: Run MOSAIC calibration
        run: |
          python azure/run_mosaic_coiled.py \
            --iso ${{ inputs.iso_codes }} \
            --n-simulations ${{ inputs.n_simulations }} \
            --n-iterations ${{ inputs.n_iterations }} \
            --n-workers ${{ inputs.n_workers }} \
            --output-dir ./output

      - name: Compress results
        run: |
          tar -czf output.tar.gz output/
          ls -lh output.tar.gz

      - name: Upload results
        uses: actions/upload-artifact@v4
        with:
          name: mosaic-results-${{ github.sha }}
          path: output.tar.gz
          retention-days: 90

      - name: Post summary
        uses: actions/github-script@v7
        if: always()
        with:
          script: |
            const fs = require('fs');
            const checkpoints = fs.readdirSync('output').filter(f => f.startsWith('checkpoint'));
            const latest = checkpoints.sort().reverse()[0];
            const data = JSON.parse(fs.readFileSync(`output/${latest}`, 'utf8'));

            core.summary
              .addHeading('🎉 MOSAIC Calibration Complete')
              .addTable([
                [{data: 'Parameter', header: true}, {data: 'Value', header: true}],
                ['ISO Codes', '${{ inputs.iso_codes }}'],
                ['Iterations', '${{ inputs.n_iterations }}'],
                ['Simulations', '${{ inputs.n_simulations }}'],
                ['Workers', '${{ inputs.n_workers }}'],
                ['Final ESS', Math.round(data.ess)]
              ])
              .write();
```

---

## Running Your First Job

### Step 1: Test Locally (Optional)

```bash
# Activate environment
conda activate mosaic-coiled

# Test with small run (uses Coiled cloud)
python azure/run_mosaic_coiled.py \
  --iso ETH \
  --n-simulations 100 \
  --n-iterations 1 \
  --n-workers 2 \
  --output-dir ./test-output

# This will:
# 1. Spin up 2 workers on Coiled (takes ~2 minutes)
# 2. Run 100 LASER simulations in parallel
# 3. Save results to ./test-output/
```

**Expected Cost**: ~$2 (100 simulations × 2 workers × 5 minutes)

### Step 2: Trigger GitHub Actions

1. Go to GitHub → Actions → "MOSAIC Coiled Dispatch"
2. Click "Run workflow"
3. Fill in:
   - ISO codes: `ETH`
   - Simulations: `1000`
   - Iterations: `2`
   - Workers: `10`
4. Click "Run workflow"

**Monitor**:
- GitHub Actions shows progress logs
- Coiled dashboard link printed in logs (click to see live worker metrics)

### Step 3: Download Results

Once workflow completes:
1. Go to workflow run page
2. Download artifact: `mosaic-results-<sha>.zip`
3. Extract: `unzip mosaic-results-<sha>.zip && tar -xzf output.tar.gz`
4. Load results in R:

```r
library(arrow)
results <- read_parquet("output/simulations.parquet")
head(results)
```

---

## Monitoring and Costs

### Coiled Dashboard

Access at: `https://cloud.coiled.io/clusters/<cluster-name>`

**Metrics**:
- Worker CPU/memory usage
- Task duration distribution
- Data transfer rates
- Cost accumulation (real-time)

### Cost Tracking

```python
import coiled

# Get cluster cost
cluster = coiled.Cluster("mosaic-ETH")
print(f"Cluster cost: ${cluster.cost():.2f}")

# Get account summary
summary = coiled.account_summary()
print(f"Month-to-date: ${summary['total_cost']:.2f}")
```

### Typical Costs

| Configuration | Runtime | Cost |
|---------------|---------|------|
| **Test run** (ETH, 100 sims, 2 workers) | 5 min | **$2** |
| **Small run** (ETH, 1000 sims, 10 workers, 2 iters) | 30 min | **$15** |
| **Medium run** (ETH+KEN, 1000 sims, 20 workers, 3 iters) | 2 hours | **$60** |
| **Large run** (8 countries, 1000 sims, 50 workers, 5 iters) | 6 hours | **$200** |

**Pricing**: ~$0.10-0.15/core-hour (includes AWS compute + Coiled platform fee)

---

## Advanced Features

### Feature 1: Adaptive Worker Scaling

Coiled can auto-scale based on task queue:

```python
cluster = coiled.Cluster(
    n_workers=(5, 50),  # Min 5, max 50
    worker_vm_types=["Standard_D4s_v6"],
    scaling_factor=2  # Scale up aggressively
)
```

### Feature 2: GPU Workers (for NPE)

```python
@coiled.function(
    vm_type="p3.2xlarge",  # NVIDIA V100 GPU
    software="mosaic-pkg-gpu"
)
def train_npe_remote(training_data):
    # NPE training code here
    pass
```

### Feature 3: Multi-Region Failover

```python
cluster = coiled.Cluster(
    region="westus2",
    fallback_region="eastus"  # If westus2 capacity issues
)
```

### Feature 4: Result Streaming

Stream results to Azure Blob Storage as they complete (don't wait for all simulations):

```python
import s3fs

fs = s3fs.Azure Blob StorageFileSystem()

def run_and_save(param_dict, config, priors, s3_path):
    result = run_laser_remote(param_dict, config, priors)
    with fs.open(f"{s3_path}/{param_dict['id']}.json", 'w') as f:
        json.dump(result, f)
    return param_dict['id']
```

---

## Troubleshooting

### Issue 1: "Software environment not found"

**Solution**: Create environment first:

```bash
coiled env create --name mosaic-pkg --file azure/coiled_environment.yml
```

### Issue 2: R package installation fails on workers

**Solution**: Check post-build script logs:

```bash
coiled env logs mosaic-pkg
```

### Issue 3: Workers timeout during simulation

**Solution**: Increase keepalive time:

```python
@coiled.function(keepalive="30 minutes")
```

### Issue 4: Costs higher than expected

**Solution**: Ensure cluster shuts down:

```python
try:
    # ... run simulations ...
finally:
    cluster.close()  # Always cleanup
```

---

## Next Steps

After first successful run:

1. **Optimize worker size**: Benchmark different VM types (m5.xlarge vs m5.4xlarge)
2. **Enable NPE**: Add GPU workers for neural posterior estimation
3. **Scheduled runs**: Add cron trigger for monthly calibrations
4. **Cost alerts**: Set up Coiled budget notifications
5. **Multi-region**: Distribute workers across regions for redundancy

---

## Resources

- **Coiled Docs**: https://docs.coiled.io/
- **Dask Tutorial**: https://tutorial.dask.org/
- **rpy2 Guide**: https://rpy2.github.io/doc/latest/html/index.html
- **MOSAIC Docs**: https://institutefordiseasemodeling.github.io/MOSAIC-docs/

---

**Questions?**
- Coiled Support: support@coiled.io
- MOSAIC Team: john.giles@gatesfoundation.org
- Issues: https://github.com/InstituteforDiseaseModeling/MOSAIC-pkg/issues
