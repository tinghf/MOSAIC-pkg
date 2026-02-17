# MOSAIC Distributed Computing Options

## Current Implementation: Single-Node Parallelism

**Architecture:**
```
Main R Process
    ↓
parallel::makeCluster(n_cores) [PSOCK/FORK]
    ↓
Workers (on same machine)
    ├─ Worker 1: Initialize Python → Run LASER sims
    ├─ Worker 2: Initialize Python → Run LASER sims
    └─ Worker N: Initialize Python → Run LASER sims
```

**Limitations:**
- Limited to cores on single machine (~120 cores max on VM)
- All workers share same memory/CPU resources
- Cannot scale beyond single node

**Location:** [R/run_MOSAIC.R:641](R/run_MOSAIC.R#L641)
```r
cl <- parallel::makeCluster(control$parallel$n_cores, type = control$parallel$type)
parallel::parLapply(cl, sim_ids, worker_func)
```

---

## Option 1: Dask (Python Distributed Framework) ⭐ RECOMMENDED

### Why Dask for MOSAIC?

**Advantages:**
- Native Python framework (LASER is Python-based)
- Scales from single machine to HPC clusters
- Automatic task scheduling and load balancing
- Built-in progress monitoring dashboard
- Fault tolerance (auto-retry failed tasks)
- Minimal code changes needed

**Architecture:**
```
Dask Scheduler (head node)
    ↓
Dask Workers (multiple nodes)
    ├─ Node 1: [Worker 1, Worker 2, ...]
    ├─ Node 2: [Worker 1, Worker 2, ...]
    └─ Node N: [Worker 1, Worker 2, ...]
```

### Implementation Strategy

**Phase 1: Python wrapper for LASER simulations**

Create `inst/python/dask_laser_runner.py`:

```python
import dask
from dask.distributed import Client, progress
import numpy as np
from laser_cholera.metapop.model import run_model

def run_single_simulation(sim_id, config_template, priors, n_iterations, seed_base):
    """
    Single LASER simulation (runs on remote worker).

    Returns: (sim_id, success, results_dict)
    """
    try:
        # Sample parameters (deterministic given seed)
        np.random.seed(sim_id)  # Use sim_id as seed for reproducibility

        # Sample from priors (simplified - actual sampling in R)
        params = config_template.copy()
        params['seed'] = seed_base + sim_id

        # Run LASER model
        model = run_model(paramfile=params, quiet=True)

        # Extract results
        results = {
            'sim_id': sim_id,
            'cases': model.results.expected_cases.tolist(),
            'deaths': model.results.disease_deaths.tolist(),
            'success': True
        }

        return results

    except Exception as e:
        return {
            'sim_id': sim_id,
            'success': False,
            'error': str(e)
        }


def run_batch_distributed(sim_ids, config_template, priors,
                          n_iterations, scheduler_address=None):
    """
    Run batch of simulations using Dask distributed.

    Args:
        sim_ids: List of simulation IDs to run
        config_template: Base LASER config
        priors: Parameter priors
        n_iterations: Iterations per simulation
        scheduler_address: Dask scheduler address (e.g., 'tcp://10.0.0.1:8786')
                          If None, creates local cluster
    """

    # Connect to Dask cluster
    client = Client(scheduler_address) if scheduler_address else Client()

    print(f"Dask cluster: {client.dashboard_link}")
    print(f"Workers: {len(client.scheduler_info()['workers'])}")

    # Create lazy tasks (not executed yet)
    futures = []
    for sim_id in sim_ids:
        future = client.submit(
            run_single_simulation,
            sim_id=sim_id,
            config_template=config_template,
            priors=priors,
            n_iterations=n_iterations,
            seed_base=10000
        )
        futures.append(future)

    # Show progress
    progress(futures)

    # Gather results (blocks until all complete)
    results = client.gather(futures)

    return results
```

**Phase 2: R interface to Dask**

Create `R/run_MOSAIC_dask.R`:

```r
#' Run MOSAIC calibration with Dask distributed computing
#'
#' @param scheduler_address Dask scheduler address (e.g., 'tcp://10.0.0.1:8786')
#'   If NULL, starts local Dask cluster
#' @param n_workers Number of Dask workers to spawn (if local cluster)
#' @export
run_MOSAIC_dask <- function(config, priors,
                            scheduler_address = NULL,
                            n_workers = NULL,
                            control = mosaic_control_defaults()) {

  # Import Dask runner
  dask_runner <- reticulate::import_from_path(
    "dask_laser_runner",
    path = system.file("python", package = "MOSAIC")
  )

  # Setup directories (same as run_MOSAIC)
  dirs <- .mosaic_setup_directories(control$paths$dir_output, control$paths$clean_output)

  # Get simulation IDs
  sim_ids <- seq_len(control$calibration$n_simulations)

  message("Starting Dask distributed calibration...")
  message("Scheduler: ", scheduler_address %||% "local cluster")

  # Run batch using Dask
  results <- dask_runner$run_batch_distributed(
    sim_ids = as.integer(sim_ids),
    config_template = config,
    priors = priors,
    n_iterations = as.integer(control$calibration$n_iterations),
    scheduler_address = scheduler_address
  )

  # Process results (same as run_MOSAIC)
  results_df <- process_dask_results(results)

  # Save to parquet
  arrow::write_parquet(results_df, file.path(dirs$bfrs_out, "simulations.parquet"))

  message("Calibration complete!")
  return(results_df)
}
```

**Phase 3: Launch Dask cluster on HPC**

Create `vm/launch_dask_cluster.sh`:

```bash
#!/bin/bash
# Launch Dask cluster across multiple nodes

# Configuration
N_NODES=10
CORES_PER_NODE=120
SCHEDULER_NODE="node-001"

# Start scheduler on head node
ssh $SCHEDULER_NODE "source ~/miniforge3/etc/profile.d/conda.sh && \
    conda activate mosaic-conda-env && \
    dask-scheduler --port 8786 --dashboard-address :8787 &"

sleep 5

# Get scheduler address
SCHEDULER_IP=$(ssh $SCHEDULER_NODE "hostname -i")
SCHEDULER_ADDRESS="tcp://${SCHEDULER_IP}:8786"

echo "Dask scheduler: $SCHEDULER_ADDRESS"
echo "Dashboard: http://${SCHEDULER_IP}:8787"

# Start workers on compute nodes
for i in $(seq 2 $N_NODES); do
    NODE="node-$(printf '%03d' $i)"
    echo "Starting worker on $NODE..."

    ssh $NODE "source ~/miniforge3/etc/profile.d/conda.sh && \
        conda activate mosaic-conda-env && \
        dask-worker $SCHEDULER_ADDRESS \
            --nthreads 1 \
            --nworkers $CORES_PER_NODE \
            --memory-limit 4GB &"
done

echo "Cluster ready!"
echo "Connect from R with: run_MOSAIC_dask(scheduler_address='$SCHEDULER_ADDRESS')"
```

**Usage in R:**

```r
# Launch from head node after starting Dask cluster
config <- get_location_config(iso = "ETH")
priors <- get_location_priors(iso = "ETH")

results <- run_MOSAIC_dask(
  config = config,
  priors = priors,
  scheduler_address = "tcp://10.0.0.1:8786",  # From launch script
  control = control
)
```

---

## Option 2: future.batchtools (R Native HPC) ⭐ EASIEST

### Why future.batchtools?

**Advantages:**
- Pure R solution (minimal code changes)
- Native Slurm support
- Drop-in replacement for parallel::parLapply
- Works with existing MOSAIC code

**Architecture:**
```
Main R Process
    ↓
future.batchtools → Slurm Scheduler
    ↓
Slurm Jobs (multiple nodes)
    ├─ Job 1 (Node 1): LASER sims
    ├─ Job 2 (Node 2): LASER sims
    └─ Job N (Node N): LASER sims
```

### Implementation

**Step 1: Modify run_MOSAIC.R**

Replace the cluster creation section:

```r
# In R/run_MOSAIC.R, around line 641

if (control$parallel$backend == "slurm") {
  # Use future.batchtools for Slurm
  library(future.batchtools)

  plan(batchtools_slurm,
       template = system.file("templates", "slurm.tmpl", package = "MOSAIC"),
       workers = control$parallel$n_nodes,
       resources = list(
         nodes = 1,
         cpus = control$parallel$cores_per_node,
         memory = "100GB",
         walltime = "24:00:00",
         partition = "compute"
       ))

  # Use future_lapply instead of parLapply
  library(future.apply)

  .mosaic_run_batch <- function(sim_ids, worker_func, cl, show_progress) {
    future_lapply(sim_ids, worker_func,
                  future.seed = TRUE,
                  future.scheduling = 1.0)  # Dynamic load balancing
  }

} else {
  # Original parallel::makeCluster code
  cl <- parallel::makeCluster(control$parallel$n_cores, type = control$parallel$type)
  # ... existing code ...
}
```

**Step 2: Create Slurm template**

Create `inst/templates/slurm.tmpl`:

```bash
#!/bin/bash
#SBATCH --job-name=MOSAIC_<%= job.name %>
#SBATCH --output=<%= log.file %>
#SBATCH --error=<%= log.file %>
#SBATCH --nodes=<%= resources$nodes %>
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=<%= resources$cpus %>
#SBATCH --mem=<%= resources$memory %>
#SBATCH --time=<%= resources$walltime %>
#SBATCH --partition=<%= resources$partition %>

# Load environment
source ~/miniforge3/etc/profile.d/conda.sh
conda activate mosaic-conda-env

# Set threading limits
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export NUMBA_NUM_THREADS=1
export TBB_NUM_THREADS=1

# Run R script
Rscript -e 'batchtools::doJobCollection("<%= uri %>")'
```

**Usage:**

```r
# Same as before, but specify backend
control <- mosaic_control_defaults()
control$parallel$backend <- "slurm"
control$parallel$n_nodes <- 10
control$parallel$cores_per_node <- 120

results <- run_MOSAIC(config, priors, control = control)

# Automatically submits 10 Slurm jobs across cluster!
```

---

## Option 3: Ray (Modern Alternative to Dask)

### Why Ray?

**Advantages:**
- Faster than Dask for simple embarrassingly parallel tasks
- Better fault tolerance
- Lower overhead
- Popular in ML/AI community

**Implementation:**

```python
# inst/python/ray_laser_runner.py

import ray
from laser_cholera.metapop.model import run_model

# Initialize Ray (connects to cluster if exists, otherwise local)
ray.init(address='auto')  # auto-discovers Ray cluster

@ray.remote
def run_simulation_ray(sim_id, config, priors, n_iterations):
    """Remote function (runs on any worker in cluster)"""
    try:
        # Sample parameters and run LASER
        model = run_model(paramfile=config, quiet=True)
        return {
            'sim_id': sim_id,
            'success': True,
            'cases': model.results.expected_cases.tolist(),
            'deaths': model.results.disease_deaths.tolist()
        }
    except Exception as e:
        return {'sim_id': sim_id, 'success': False, 'error': str(e)}


def run_batch_ray(sim_ids, config, priors, n_iterations):
    """Submit all tasks and gather results"""

    # Submit all tasks (non-blocking)
    futures = [
        run_simulation_ray.remote(sim_id, config, priors, n_iterations)
        for sim_id in sim_ids
    ]

    # Wait for completion with progress bar
    results = []
    for future in futures:
        result = ray.get(future)  # Blocks until this task completes
        results.append(result)
        print(f"Completed: {len(results)}/{len(sim_ids)}", end='\r')

    return results
```

**Launch Ray cluster:**

```bash
# On head node
ray start --head --port=6379 --dashboard-port=8265

# On worker nodes
ray start --address='head-node-ip:6379'

# View dashboard: http://head-node-ip:8265
```

---

## Option 4: Slurm Array Jobs (HPC Standard)

### Why Slurm Arrays?

**Advantages:**
- Standard HPC approach
- No dependencies beyond Slurm
- Maximum portability
- Simple to debug

**Implementation:**

Create `vm/run_mosaic_array.sh`:

```bash
#!/bin/bash
#SBATCH --job-name=MOSAIC_calibration
#SBATCH --array=1-10000%100  # 10k simulations, max 100 concurrent
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4GB
#SBATCH --time=01:00:00
#SBATCH --output=logs/sim_%a.log

# Get simulation ID from array task ID
SIM_ID=$SLURM_ARRAY_TASK_ID

# Run single simulation
Rscript -e "
  library(MOSAIC)
  attach_mosaic_env()

  # Load config (shared via filesystem)
  config <- readRDS('output/setup/config.rds')
  priors <- readRDS('output/setup/priors.rds')

  # Run single simulation
  result <- .mosaic_run_simulation_worker(
    sim_id = $SIM_ID,
    n_iterations = 3,
    priors = priors,
    config = config,
    PATHS = get_paths(),
    dir_bfrs_parameters = 'output/1_bfrs/parameters',
    dir_bfrs_timeseries = NULL,
    param_names_all = names(convert_config_to_matrix(config)),
    sampling_args = list(),
    io = list(format = 'parquet'),
    save_timeseries = FALSE
  )

  cat('Simulation', $SIM_ID, 'completed\n')
"
```

**Launcher R script:**

```r
# Prepare configs
config <- get_location_config(iso = "ETH")
priors <- get_location_priors(iso = "ETH")

dir.create("output/setup", recursive = TRUE)
saveRDS(config, "output/setup/config.rds")
saveRDS(priors, "output/setup/priors.rds")

# Submit array job
system("sbatch vm/run_mosaic_array.sh")

# Monitor: squeue -u $USER

# After completion, combine results
files <- list.files("output/1_bfrs/parameters", pattern = "^sim_.*\\.parquet$", full.names = TRUE)
results <- arrow::open_dataset(files) %>% collect()
```

---

## Comparison Matrix

| Framework | Setup | Scalability | Fault Tolerance | Code Changes | Best For |
|-----------|-------|-------------|-----------------|--------------|----------|
| **Dask** | Medium | Excellent | Excellent | Medium | Production distributed computing |
| **future.batchtools** | Easy | Excellent | Good | Minimal | Existing HPC with Slurm |
| **Ray** | Medium | Excellent | Excellent | Medium | ML-focused workflows |
| **Slurm Arrays** | Easy | Good | Good | Medium | Simple HPC batch jobs |
| **GNU Parallel + SSH** | Easy | Medium | Poor | Minimal | Quick prototyping |

---

## Recommendation for MOSAIC

**Primary Recommendation: Dask**

**Rationale:**
1. LASER is Python-based → natural fit
2. Scales seamlessly (1 node → 100 nodes)
3. Built-in monitoring dashboard
4. Fault tolerance (critical for long-running calibrations)
5. Minimal changes to MOSAIC workflow

**Secondary Recommendation: future.batchtools**

**Rationale:**
1. Pure R → minimal disruption to existing code
2. Works immediately on Slurm clusters
3. Drop-in replacement for parallel::makeCluster
4. Easier to maintain long-term

**Quick Win: Slurm Arrays**

**Rationale:**
1. Simplest to implement
2. No new dependencies
3. Standard HPC approach
4. Easy to debug

---

## Implementation Roadmap

### Phase 1: Prototype (1-2 weeks)
- [ ] Implement Slurm array job approach (proof of concept)
- [ ] Test with 1000 simulations on 10 nodes
- [ ] Benchmark vs single-node parallel

### Phase 2: Production (2-4 weeks)
- [ ] Implement Dask backend in `run_MOSAIC_dask.R`
- [ ] Add `control$parallel$backend` option ("local", "dask", "slurm")
- [ ] Create cluster launch scripts
- [ ] Add monitoring/logging

### Phase 3: Documentation (1 week)
- [ ] Update CLAUDE.md with distributed computing guide
- [ ] Create HPC deployment vignette
- [ ] Add troubleshooting section

---

## Testing Checklist

- [ ] Single node: 120 cores (baseline)
- [ ] Multi-node: 2 nodes × 120 cores
- [ ] Multi-node: 10 nodes × 120 cores
- [ ] Fault tolerance: Kill random worker mid-run
- [ ] Resume: Stop and restart calibration
- [ ] Results validation: Compare Dask vs parallel output
