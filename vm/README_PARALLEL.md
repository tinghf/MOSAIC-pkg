# Parallel Multi-Country MOSAIC Runs

This directory contains scripts for running MOSAIC calibrations across multiple countries in parallel on different compute nodes.

## Overview

When running MOSAIC for multiple countries, you have two options:

1. **Coupled Multi-Country Model** (original approach)
   - All countries in one `run_MOSAIC()` call
   - Models mobility/coupling between countries
   - Requires sampling mobility parameters
   - Runs on a single node with internal parallelization

2. **Independent Country Models** (new approach, this directory)
   - Each country runs separately on its own compute node
   - No mobility coupling between countries
   - Ideal for HPC clusters or multiple VMs
   - Maximum parallelization

## Quick Start

### Option A: HPC Cluster with SLURM

```bash
# Submit all countries as a job array
sbatch vm/submit_parallel_countries_slurm.sh

# Monitor jobs
squeue -u $USER

# Check specific country output
tail -f logs/mosaic_<JOBID>_<ARRAYID>.out
```

### Option B: HPC Cluster with PBS/Torque

```bash
# Submit all countries as a job array
qsub vm/submit_parallel_countries_pbs.sh

# Monitor jobs
qstat -u $USER

# Check specific country output
tail -f logs/mosaic_<JOBID>.out
```

### Option C: Multiple VMs/Machines (No Scheduler)

**Approach 1: Automated background submission**
```bash
# Launch all countries in background on one machine
bash vm/submit_parallel_countries_local.sh

# Monitor progress
tail -f logs/mosaic_ETH.out

# Check all running jobs
ps aux | grep run_single_country.R
```

**Approach 2: Manual distribution across VMs**

On VM 1 (for Ethiopia):
```bash
nohup Rscript vm/run_single_country.R ETH > logs/mosaic_ETH.out 2>&1 &
```

On VM 2 (for Kenya):
```bash
nohup Rscript vm/run_single_country.R KEN > logs/mosaic_KEN.out 2>&1 &
```

On VM 3 (for Tanzania):
```bash
nohup Rscript vm/run_single_country.R TZA > logs/mosaic_TZA.out 2>&1 &
```

...and so on for each country.

## Files in This Directory

| File | Purpose |
|------|---------|
| `run_single_country.R` | Main R script for single country calibration |
| `submit_parallel_countries_slurm.sh` | SLURM job array submission script |
| `submit_parallel_countries_pbs.sh` | PBS/Torque job array submission script |
| `submit_parallel_countries_local.sh` | Background submission for local machines |
| `collect_parallel_results.R` | Collect and summarize results from all countries |
| `README_PARALLEL.md` | This file |

## Collecting Results

After countries finish running:

```r
# Check completion status and aggregate results
Rscript vm/collect_parallel_results.R
```

This will:
- Check which countries completed successfully
- Report number of simulations per country
- Calculate total output sizes
- Create a summary CSV: `~/MOSAIC/output/parallel_run_status.csv`

## Output Structure

Each country gets its own output directory:

```
~/MOSAIC/output/
├── MOZ/                    # Mozambique
│   ├── 0_setup/
│   ├── 1_bfrs/
│   │   └── outputs/
│   │       └── simulations.parquet
│   └── ...
├── MWI/                    # Malawi
│   ├── 0_setup/
│   ├── 1_bfrs/
│   └── ...
├── ETH/                    # Ethiopia
│   └── ...
└── parallel_run_status.csv   # Summary table
```

## Customizing Your Run

### Change Countries

Edit the country list in the submission scripts:

```bash
# In submit_parallel_countries_*.sh
COUNTRIES=(
  "ETH"  # Ethiopia
  "SOM"  # Somalia
  "KEN"  # Kenya
  # Add more countries...
)
```

**Important**: Adjust `--array=0-N` (SLURM) or `-t 0-N` (PBS) to match the number of countries (N+1).

### Adjust Resources

Edit resource requests in submission scripts:

```bash
# SLURM
#SBATCH --cpus-per-task=64    # More cores for larger countries
#SBATCH --mem=128G            # More memory for complex models
#SBATCH --time=48:00:00       # Longer runtime

# PBS
#PBS -l nodes=1:ppn=64
#PBS -l mem=128gb
#PBS -l walltime=48:00:00
```

### Modify Calibration Settings

Edit [run_single_country.R](run_single_country.R):

```r
# Longer calibration
control$calibration$n_iterations <- 5

# Higher convergence targets
control$targets$ESS_param <- 2000

# Enable NPE
control$npe$enable <- TRUE
```

## Performance Guidelines

**Typical runtimes** (approximate, depends on data size):
- Small countries (e.g., Burundi): 2-6 hours
- Medium countries (e.g., Kenya): 6-12 hours
- Large countries (e.g., Nigeria): 12-24+ hours

**Resource recommendations**:
- **CPUs**: 16-32 cores per country (diminishing returns beyond 32)
- **Memory**: 32-64 GB per country (increase for large populations)
- **Storage**: 5-20 GB per country for outputs

**Scaling**: With 8 compute nodes (one per country), you can calibrate all East African countries in the same time it would take to run one country sequentially.

## Troubleshooting

**Job fails with "library not found"**:
```bash
# Ensure R library path is set correctly
mkdir -p ~/R/library
echo 'R_LIBS_USER=~/R/library' >> ~/.Renviron
```

**Python environment errors**:
```bash
# Verify conda environment exists
conda env list | grep mosaic

# Recreate if needed
Rscript -e 'MOSAIC::install_dependencies(force=TRUE)'
```

**Out of memory**:
- Reduce `control$calibration$batch_size`
- Increase node memory allocation
- Use `control$io <- mosaic_io_presets("minimal")` to reduce memory footprint

**Job hangs/segfaults**:
- Check that threading limits are set (handled automatically in `run_single_country.R`)
- Ensure OpenMP libraries are compatible (handled by `.onLoad()` in MOSAIC package)

## Comparison: Coupled vs Independent

| Aspect | Coupled Multi-Country | Independent Countries |
|--------|----------------------|----------------------|
| **Execution** | Single `run_MOSAIC()` call | Multiple parallel jobs |
| **Mobility** | Models cross-border transmission | No mobility coupling |
| **Parallelization** | Within-node only | Across multiple nodes |
| **Runtime** | Slower (sequential countries) | Faster (true parallelization) |
| **Resources** | One large node | Multiple smaller nodes |
| **Use case** | Studying regional outbreaks | Country-specific calibration |

**When to use independent runs**:
- You have access to multiple compute nodes/VMs
- Countries have distinct epidemic patterns
- You want maximum computational efficiency
- You're calibrating many countries (>5)

**When to use coupled runs**:
- You're studying cross-border transmission
- You have mobility/travel data between countries
- You need to model regional epidemics
- You're running few countries (<3) on one large node

## Example: Starsim Hedgehog Server

On the Hedgehog server (120 cores, 456GB RAM), you could:

**Option 1: Run 4 countries in parallel on one VM**
```bash
# Each country uses 30 cores
bash vm/submit_parallel_countries_local.sh
# (manually kill all but 4 countries to avoid oversubscription)
```

**Option 2: Provision 8 separate VMs, run 1 country per VM**
```bash
# On each VM (e.g., Standard_D16s_v3: 16 cores, 64GB)
Rscript vm/run_single_country.R <ISO_CODE>
```

Option 2 gives you 8x parallelization with better resource isolation.
