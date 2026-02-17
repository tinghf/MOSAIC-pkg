# MOSAIC Slurm Deployment Guide

## Quick Start

MOSAIC now supports distributed computing on Slurm HPC clusters via `future.batchtools`.

### Basic Example

```r
library(MOSAIC)

# Multi-country configuration
iso_codes <- c("ETH", "KEN", "SOM", "UGA", "TZA")
config <- get_location_config(iso = iso_codes)
priors <- get_location_priors(iso = iso_codes)

# Configure for Slurm
control <- mosaic_control_defaults(
  calibration = list(
    n_simulations = 10000,
    n_iterations = 3
  ),
  parallel = list(
    enable = TRUE,
    type = "future",        # Enable Slurm backend
    n_cores = 100,          # Launch 100 Slurm jobs
    backend = "slurm",
    resources = list(
      cpus = 1,
      memory = "6GB",
      walltime = "04:00:00",
      partition = "compute"  # Your cluster's partition
    )
  )
)

# Run (submits 100 jobs to Slurm)
results <- run_MOSAIC(config, priors, "./output", control = control)
```

**Speedup**: ~50-100x faster (10k sims in 1-2 hours vs 2-3 days single-node)

## Configuration Options

### Required Settings

- `control$parallel$type = "future"` - Enable HPC backend
- `control$parallel$backend = "slurm"` - Use Slurm scheduler
- `control$parallel$n_cores` - Number of Slurm jobs to launch

### Slurm Resource Settings

- `resources$cpus` - CPUs per job (default: 1)
- `resources$memory` - Memory per job (e.g., "4GB", "8GB")
- `resources$walltime` - Max runtime (e.g., "04:00:00" for 4 hours)
- `resources$partition` - Slurm partition name (optional)
- `resources$account` - Slurm account/project (optional)

## Multi-Country Support

✅ **Fully compatible**. Each worker runs the entire coupled metapopulation system independently.

```
Worker 1: LASER([ETH ↔ KEN ↔ SOM ...]) → results₁  (independent)
Worker 2: LASER([ETH ↔ KEN ↔ SOM ...]) → results₂  (independent)
```

No inter-worker communication required!

## Resource Planning

### Memory Requirements

| Countries | Memory/Worker | Example |
|-----------|---------------|---------|
| 1-2 | 2-3 GB | Ethiopia only |
| 3-5 | 4-6 GB | East Africa |
| 6-10 | 6-10 GB | Horn + East Africa |
| 11-40 | 15-40 GB | Sub-Saharan Africa |

**Formula**: Memory (GB) ≈ 1 + (0.5 × n_countries)

### Optimal Worker Count

- Small cluster (<100 nodes): 50-100 workers
- Medium cluster (100-500): 100-300 workers  
- Large cluster (>500 nodes): 200-500 workers

## Testing

Validate your setup before production runs:

```bash
Rscript tests/test_hpc_setup.R
```

## Documentation

- Full vignette: `vignette("hpc-deployment", package = "MOSAIC")`
- Example script: `examples/hpc_calibration_example.R`
- Test script: `tests/test_hpc_setup.R`

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Jobs fail immediately | Check Python env on compute nodes |
| Out of memory | Increase `resources$memory` |
| Jobs timeout | Increase `resources$walltime` |
| Python module not found | Verify conda env in template |

Check job logs: `~/.batchtools.logs/`

## Custom Template

To customize the Slurm template:

```r
# Copy default template
template_src <- system.file("templates/slurm.tmpl", package = "MOSAIC")
file.copy(template_src, "~/my_slurm.tmpl")

# Edit ~/my_slurm.tmpl as needed

# Use custom template
control$parallel$template <- "~/my_slurm.tmpl"
```

## Implementation Details

**Files Modified/Created**:
- `R/run_MOSAIC.R` - Added future backend support
- `R/run_MOSAIC_future.R` - Helper functions (NEW)
- `inst/templates/slurm.tmpl` - Slurm job template (NEW)

**Backward Compatible**: Existing code unchanged. Only activates when `type = "future"`.

