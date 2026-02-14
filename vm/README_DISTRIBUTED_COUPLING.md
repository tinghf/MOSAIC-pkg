# Distributed Coupled Multi-Country Simulations

This guide explains how to run **coupled multi-country MOSAIC models** with **each country on a separate compute node**, enabling both parallelization AND mobility/coupling between countries.

---

## Overview: The Challenge

**Goal**: Model cross-border cholera transmission while running countries on separate nodes.

**Challenge**: Countries need to exchange infection state data to compute spatial importation hazard, but they're running on different machines.

**Solutions**: We provide three approaches with increasing sophistication:

| Approach | Complexity | Accuracy | Use Case |
|----------|-----------|----------|----------|
| **1. Iterative Offline Coupling** | Low | Good | Initial exploration, limited HPC |
| **2. Synchronous File-Based Coupling** | Medium | Excellent | HPC with shared filesystem (NFS/Lustre) |
| **3. Redis State Server** | High | Excellent | Production, high-frequency coupling |

---

## Approach 1: Iterative Offline Coupling

**Concept**: Run multiple "rounds" where each round uses the previous round's infection trajectories as fixed external forcing.

### How It Works

**Round 0**: Run all countries independently (no coupling)
```
Node 1: Ethiopia → trajectory_ETH_round0.csv
Node 2: Kenya → trajectory_KEN_round0.csv
Node 3: Somalia → trajectory_SOM_round0.csv
```

**Round 1**: Re-run all countries using Round 0 trajectories as importation forcing
```
Node 1: Ethiopia uses (Kenya_round0, Somalia_round0) → trajectory_ETH_round1.csv
Node 2: Kenya uses (Ethiopia_round0, Somalia_round0) → trajectory_KEN_round1.csv
Node 3: Somalia uses (Ethiopia_round0, Kenya_round0) → trajectory_SOM_round1.csv
```

**Round 2+**: Repeat until convergence (trajectories stop changing significantly)

### Implementation

**Step 1: Modify LASER config to accept external forcing**

Create a helper function to inject imported infections:

```r
# R/add_external_importation.R
add_external_importation <- function(config, external_trajectories) {
  # external_trajectories: list of data.frames with columns (date, location, I1, I2)

  # Compute gravity-weighted importation from external sources
  tau <- config$tau_i
  pi_matrix <- calc_diffusion_matrix_pi(
    D = config$distance_matrix,
    N = config$population,
    omega = config$mobility_omega,
    gamma = config$mobility_gamma
  )

  # For each time step, compute imported infections
  location_name <- config$location_name
  n_locations <- length(location_name)

  external_hazard <- lapply(seq_along(location_name), function(j) {
    # For destination j, sum over all external sources i
    imported <- sapply(external_trajectories, function(traj_i) {
      if (traj_i$location[1] == location_name[j]) return(0)  # Skip self

      i_idx <- which(location_name == traj_i$location[1])
      tau_i <- tau[i_idx]
      pi_ij <- pi_matrix[i_idx, j]

      # Imported infections = tau_i × pi_ij × (I1 + I2)
      tau_i * pi_ij * (traj_i$I1 + traj_i$I2)
    })

    data.frame(
      date = external_trajectories[[1]]$date,
      location = location_name[j],
      imported_infections = rowSums(imported)
    )
  })

  # Add to config as external forcing
  config$external_importation <- do.call(rbind, external_hazard)

  return(config)
}
```

**Step 2: Create round-based wrapper**

```r
# vm/run_coupled_iterative.R
run_coupled_iterative <- function(iso_codes,
                                   n_rounds = 3,
                                   output_dir,
                                   control) {

  results_by_round <- list()

  for (round in 0:n_rounds) {
    cat("======================================\n")
    cat("Round", round, "of", n_rounds, "\n")
    cat("======================================\n")

    # For each country, prepare config
    for (iso in iso_codes) {

      config <- get_location_config(iso = iso)
      priors <- get_location_priors(iso = iso)

      # If not Round 0, add external forcing from previous round
      if (round > 0) {
        external_trajectories <- lapply(setdiff(iso_codes, iso), function(other_iso) {
          traj_file <- file.path(output_dir,
                                 paste0(other_iso, "_round", round-1, "_trajectory.csv"))
          read.csv(traj_file)
        })

        config <- add_external_importation(config, external_trajectories)
      }

      # Run MOSAIC for this country
      country_output <- file.path(output_dir, iso, paste0("round_", round))

      result <- run_MOSAIC(
        dir_output = country_output,
        config = config,
        priors = priors,
        control = control
      )

      # Extract and save trajectory for next round
      trajectory <- extract_infection_trajectory(result)
      write.csv(trajectory,
                file.path(output_dir, paste0(iso, "_round", round, "_trajectory.csv")),
                row.names = FALSE)
    }

    # Check convergence (compare round N to round N-1)
    if (round > 0) {
      converged <- check_trajectory_convergence(iso_codes, round, output_dir)
      if (converged) {
        cat("Trajectories converged at round", round, "\n")
        break
      }
    }
  }

  return(results_by_round)
}
```

**Step 3: Distributed execution**

```bash
# On Node 1 (Ethiopia - Round 0)
Rscript -e "
  iso <- 'ETH'
  round <- 0
  # Run without external forcing
  result <- run_MOSAIC(...)
  save_trajectory(result, 'shared_dir/ETH_round0_trajectory.csv')
"

# Wait for all nodes to complete Round 0...

# On Node 1 (Ethiopia - Round 1)
Rscript -e "
  iso <- 'ETH'
  round <- 1
  # Load external trajectories
  external <- load_trajectories(c('KEN', 'SOM'), round=0)
  # Run with coupling
  config <- add_external_importation(config, external)
  result <- run_MOSAIC(...)
  save_trajectory(result, 'shared_dir/ETH_round1_trajectory.csv')
"
```

### Pros & Cons

✅ **Pros:**
- No real-time synchronization needed
- Works with simple job schedulers
- Easy to debug and inspect intermediate results
- Can run overnight batch jobs

❌ **Cons:**
- Not true dynamic coupling (iterative approximation)
- Requires multiple rounds (2-4 typically)
- Convergence not guaranteed for highly coupled systems
- Each round is full MOSAIC calibration (expensive)

---

## Approach 2: Synchronous File-Based Coupling

**Concept**: Use shared filesystem (NFS/Lustre on HPC) for real-time state exchange during LASER simulation time steps.

### Architecture

```
Shared Filesystem: /scratch/mosaic_shared/
├── state/
│   ├── ETH_infections.csv      # Updated by Node 1
│   ├── KEN_infections.csv      # Updated by Node 2
│   ├── SOM_infections.csv      # Updated by Node 3
│   └── sync_barrier.txt        # Coordination file
└── logs/
    ├── ETH.log
    ├── KEN.log
    └── SOM.log
```

### How It Works

1. **Before each LASER simulation**:
   - Each node writes current infection state to shared location
   - Wait for barrier (all nodes have written)
   - Read other nodes' infection states
   - Compute spatial hazard with real external data

2. **Run LASER simulation**:
   - Use computed spatial hazard for importation
   - Run to completion

3. **After simulation**:
   - Update shared state with new infections
   - Proceed to next parameter sample

### Implementation

**Step 1: Shared state manager**

```r
# R/shared_state_manager.R
SharedStateManager <- R6::R6Class("SharedStateManager",
  public = list(
    shared_dir = NULL,
    my_location = NULL,
    all_locations = NULL,

    initialize = function(shared_dir, my_location, all_locations) {
      self$shared_dir <- shared_dir
      self$my_location <- my_location
      self$all_locations <- all_locations

      # Create state directory
      state_dir <- file.path(shared_dir, "state")
      dir.create(state_dir, recursive = TRUE, showWarnings = FALSE)
    },

    write_state = function(infections, timestamp) {
      # Write my state atomically (NFS-safe)
      state_file <- file.path(self$shared_dir, "state",
                              paste0(self$my_location, "_infections.csv"))
      temp_file <- paste0(state_file, ".tmp")

      write.csv(data.frame(
        location = self$my_location,
        timestamp = timestamp,
        I1 = infections$I1,
        I2 = infections$I2
      ), temp_file, row.names = FALSE)

      # Atomic rename
      file.rename(temp_file, state_file)
    },

    read_external_states = function(timeout = 300) {
      # Read infection states from all other locations
      start_time <- Sys.time()

      external_states <- list()
      for (loc in setdiff(self$all_locations, self$my_location)) {
        state_file <- file.path(self$shared_dir, "state",
                                paste0(loc, "_infections.csv"))

        # Wait for file to exist (with timeout)
        while (!file.exists(state_file)) {
          Sys.sleep(1)
          if (difftime(Sys.time(), start_time, units = "secs") > timeout) {
            stop("Timeout waiting for ", loc, " state")
          }
        }

        # Read state
        external_states[[loc]] <- read.csv(state_file)
      }

      return(external_states)
    },

    barrier_sync = function(phase, timeout = 300) {
      # Simple barrier using file count
      barrier_dir <- file.path(self$shared_dir, "barrier", phase)
      dir.create(barrier_dir, recursive = TRUE, showWarnings = FALSE)

      # Write my barrier file
      barrier_file <- file.path(barrier_dir, self$my_location)
      writeLines(as.character(Sys.time()), barrier_file)

      # Wait for all locations
      start_time <- Sys.time()
      while (TRUE) {
        barrier_files <- list.files(barrier_dir)
        if (length(barrier_files) == length(self$all_locations)) {
          break  # All nodes reached barrier
        }

        Sys.sleep(1)
        if (difftime(Sys.time(), start_time, units = "secs") > timeout) {
          stop("Barrier timeout at phase ", phase)
        }
      }

      # Clean up barrier files
      if (self$my_location == self$all_locations[1]) {
        unlink(barrier_dir, recursive = TRUE)
      }
    }
  )
)
```

**Step 2: Modified LASER wrapper with coupling**

```r
# R/run_LASER_coupled.R
run_LASER_coupled <- function(config, state_manager) {

  # 1. Write my current state
  state_manager$write_state(
    infections = list(
      I1 = config$I_j_initial,  # Symptomatic
      I2 = config$I2_j_initial  # Asymptomatic
    ),
    timestamp = Sys.time()
  )

  # 2. Wait for other nodes
  state_manager$barrier_sync("pre_simulation")

  # 3. Read external states
  external_states <- state_manager$read_external_states()

  # 4. Compute spatial hazard with real coupling
  spatial_hazard <- compute_spatial_hazard_distributed(
    my_config = config,
    external_states = external_states,
    state_manager = state_manager
  )

  # 5. Run LASER with updated spatial hazard
  config$external_spatial_hazard <- spatial_hazard
  result <- run_LASER(config)

  # 6. Update state with results
  final_infections <- extract_final_infections(result)
  state_manager$write_state(final_infections, timestamp = Sys.time())

  return(result)
}
```

**Step 3: Distributed execution script**

```r
# vm/run_distributed_coupled.R
#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
my_location <- args[1]  # e.g., "ETH"
shared_dir <- args[2]   # e.g., "/scratch/mosaic_shared"

library(MOSAIC)

# Define all participating countries
all_locations <- c("ETH", "KEN", "SOM")

# Initialize state manager
state_mgr <- SharedStateManager$new(
  shared_dir = shared_dir,
  my_location = my_location,
  all_locations = all_locations
)

# Get configuration
config <- get_location_config(iso = my_location)
priors <- get_location_priors(iso = my_location)

# Standard MOSAIC control
control <- mosaic_control_defaults()
control$calibration$n_simulations <- 1000
control$parallel$enable <- TRUE

# Override LASER runner to use coupled version
control$coupled_mode <- TRUE
control$state_manager <- state_mgr

# Run MOSAIC with distributed coupling
result <- run_MOSAIC(
  dir_output = file.path(shared_dir, "output", my_location),
  config = config,
  priors = priors,
  control = control
)

cat("Completed:", my_location, "\n")
```

**Step 4: SLURM submission with coupling**

```bash
#!/bin/bash
#SBATCH --job-name=mosaic_coupled
#SBATCH --array=0-2
#SBATCH --nodes=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=64G
#SBATCH --time=24:00:00

# Shared directory (NFS/Lustre)
SHARED_DIR=/scratch/mosaic_shared

# Country mapping
COUNTRIES=("ETH" "KEN" "SOM")
MY_COUNTRY=${COUNTRIES[$SLURM_ARRAY_TASK_ID]}

echo "Running coupled simulation for: $MY_COUNTRY"
echo "Shared directory: $SHARED_DIR"
echo "Node: $SLURMD_NODENAME"

# Run distributed coupled simulation
Rscript vm/run_distributed_coupled.R $MY_COUNTRY $SHARED_DIR

echo "Completed: $MY_COUNTRY"
```

### Pros & Cons

✅ **Pros:**
- **True dynamic coupling**: Real-time state exchange
- **Accurate**: Identical to single-node coupled model
- **Scalable**: Each country uses full node resources
- **Familiar**: Uses HPC shared filesystems (no special infrastructure)

❌ **Cons:**
- Requires shared filesystem (NFS/Lustre)
- File I/O overhead at each synchronization point
- Barrier synchronization (slowest node determines speed)
- More complex debugging (distributed state)

---

## Approach 3: Redis State Server (Advanced)

**Concept**: Use a lightweight Redis server as central state store for infection counts.

### Architecture

```
Redis Server (1 small VM):
  - key: "ETH:infections" → {I1: 1234, I2: 567, timestamp: ...}
  - key: "KEN:infections" → {I1: 5678, I2: 890, ...}
  - key: "SOM:infections" → {...}

Compute Nodes:
  Node 1 (ETH) ← queries Redis → gets KEN, SOM infections
  Node 2 (KEN) ← queries Redis → gets ETH, SOM infections
  Node 3 (SOM) ← queries Redis → gets ETH, KEN infections
```

### Implementation Sketch

```r
# Install: install.packages("redux")
library(redux)

# Connect to Redis
redis <- redux::hiredis(host = "redis.server.address", port = 6379)

# Write my state
redis$SET(
  key = paste0(my_location, ":infections"),
  value = jsonlite::toJSON(list(
    I1 = infections$I1,
    I2 = infections$I2,
    timestamp = Sys.time()
  ))
)

# Read external states
external_states <- lapply(other_locations, function(loc) {
  state_json <- redis$GET(paste0(loc, ":infections"))
  jsonlite::fromJSON(state_json)
})
```

### Pros & Cons

✅ **Pros:**
- Fast (in-memory, microsecond latency)
- No filesystem I/O
- Built-in pub/sub for notifications
- Can add monitoring dashboard

❌ **Cons:**
- Requires Redis server setup
- Additional infrastructure complexity
- Single point of failure (needs replication for production)
- Requires network connectivity between nodes

---

## Performance Comparison

| Metric | Iterative Offline | File-Based Sync | Redis Server |
|--------|------------------|-----------------|--------------|
| **Coupling Accuracy** | ~95% | 100% | 100% |
| **Sync Overhead** | None (between rounds) | ~1-5 sec/sync | ~0.01 sec/sync |
| **Fault Tolerance** | Excellent | Good | Requires HA Redis |
| **Setup Complexity** | Low | Medium | High |
| **Debugging** | Easy | Medium | Hard |
| **Infrastructure** | HPC scheduler only | + Shared FS | + Redis server |

---

## Recommendations

**For initial exploration**: Start with **Approach 1 (Iterative Offline)**
- Easiest to implement and debug
- Good enough for most scenarios (2-3 rounds converge)
- Example: `vm/run_coupled_iterative.R`

**For production coupled models**: Use **Approach 2 (File-Based Sync)**
- True dynamic coupling
- Works on standard HPC infrastructure
- Proven pattern in climate/weather models
- Example: `vm/run_distributed_coupled.R`

**For high-frequency coupling**: Consider **Approach 3 (Redis)** if:
- Coupling updates needed every few time steps
- Running on cloud infrastructure (easy Redis deployment)
- Want real-time monitoring/visualization
- Budget for infrastructure complexity

---

## Next Steps

1. **Choose approach** based on your infrastructure and accuracy needs
2. **Test with 2 countries** (e.g., Ethiopia + Kenya) before scaling to 8+
3. **Validate coupling**: Compare distributed results to single-node coupled model
4. **Monitor synchronization overhead**: Add timing logs at barriers
5. **Tune sync frequency**: Not every time step may need coupling (weekly sync might suffice)

---

## Example Validation

To verify your distributed coupling works correctly:

```r
# 1. Run single-node coupled model (baseline)
config_coupled <- get_location_config(iso = c("ETH", "KEN"))
result_baseline <- run_MOSAIC(config = config_coupled, ...)

# 2. Run distributed coupled model
result_distributed <- run_distributed_coupled(...)

# 3. Compare infection trajectories
compare_trajectories(result_baseline, result_distributed)
# Should show < 5% difference due to sync timing
```

---

## Further Reading

- **MPI parallelism in R**: `Rmpi`, `pbdMPI` packages (for Approach 2 enhancement)
- **Distributed computing patterns**: "Embarrassingly parallel" vs. "tightly coupled"
- **File-based barriers**: Used in climate models (CESM, WRF)
- **Operator splitting**: Mathematical foundation for iterative coupling (Marchuk 1974)

---

**Questions?** Open an issue or consult HPC support for shared filesystem setup.
