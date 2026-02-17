# Multi-Country Coupling and Distributed Computing Compatibility

## TL;DR: ✅ YES - All distributed frameworks are compatible!

**Key Finding**: Multi-country coupling happens **INSIDE each LASER simulation**, not between separate simulations. Each BFRS iteration is embarrassingly parallel with NO inter-simulation communication required.

---

## Architecture: How Multi-Country Coupling Works

### Current Implementation

```
┌─────────────────────────────────────────────────────────────┐
│ BFRS Calibration Process (R)                                │
│                                                              │
│  Sample 1: params₁ → LASER → [ETH ↔ KEN ↔ SOM] → results₁  │
│  Sample 2: params₂ → LASER → [ETH ↔ KEN ↔ SOM] → results₂  │
│  Sample 3: params₃ → LASER → [ETH ↔ KEN ↔ SOM] → results₃  │
│  ...                                                         │
│  Sample N: paramsₙ → LASER → [ETH ↔ KEN ↔ SOM] → resultsₙ  │
│                                                              │
│  ↓ Calculate likelihoods                                    │
│  ↓ Update weights                                           │
│  ↓ Resample parameters                                      │
│  ↓ Check convergence                                        │
└─────────────────────────────────────────────────────────────┘

Each LASER call runs ALL countries as a coupled system internally!
```

### Inside a Single LASER Simulation

```
┌─────────────────────────────────────────────────────────────┐
│ Single LASER Simulation (Python)                            │
│                                                              │
│  ┌──────────┐   mobility   ┌──────────┐   mobility         │
│  │          │  ←─────────→  │          │  ←─────────→       │
│  │ Ethiopia │               │  Kenya   │                    │
│  │  (SEIRS) │   infection   │ (SEIRS)  │   infection        │
│  │          │    exchange   │          │    exchange        │
│  └──────────┘               └──────────┘                    │
│      ↓                           ↓                          │
│  [cases, deaths]            [cases, deaths]                 │
│                                                              │
│  Coupling handled by:                                       │
│  - Mobility matrix (M_ij): people moving between countries  │
│  - Spatial hazard (λ_spatial): infection pressure from      │
│    neighboring countries                                    │
│  - Synchronized time steps: all countries advance together  │
└─────────────────────────────────────────────────────────────┘
```

**Critical Insight**: The metapopulation coupling is handled by the LASER Python code using:
- **Mobility matrices** (M_ij) for human movement
- **Gravity model parameters** (τ_i, γ, ω) for travel probability
- **Spatial hazard calculations** (λ_spatial) for cross-border transmission

All coupling happens **within a single `run_model()` call**.

---

## Evidence from Code

### 1. Multi-Country Config Creation

From [vm/launch_mosaic.R:44-54](../vm/launch_mosaic.R#L44-L54):

```r
# Multiple countries passed to single config
iso_codes <- c("MOZ", "MWI", "ZMB", "ZWE",
               "TZA", "KEN", "ETH", "SOM")

config <- get_location_config(iso=iso_codes)
priors <- get_location_priors(iso=iso_codes)

# Mobility parameters ONLY sampled when multiple countries
control$sampling$sample_tau_i <- length(iso_codes) > 1 # Travel probability
control$sampling$sample_mobility_gamma <- length(iso_codes) > 1  # Gravity exponent
control$sampling$sample_mobility_omega <- length(iso_codes) > 1  # Mobility rate
```

### 2. Single LASER Call Handles All Countries

From [R/run_LASER.R:67-74](../R/run_LASER.R#L67-L74):

```r
# ONE call to run_model() simulates ALL countries
result <- py_module$run_model(
     paramfile = config,  # Contains multiple location_name entries
     seed      = as.integer(seed),
     quiet     = quiet,
     visualize = visualize,
     pdf       = pdf,
     outdir    = outdir
)
```

The `config` object contains:
- `location_name = c("ETH", "KEN", "SOM", ...)` (multiple countries)
- Mobility matrices between all country pairs
- Initial conditions for all countries

### 3. BFRS Simulations Are Independent

From [R/run_MOSAIC.R:75-111](../R/run_MOSAIC.R#L75-L111):

```r
# Each simulation ID gets different parameters
# but runs the SAME multi-country coupled system

for (j in 1:n_iterations) {
    seed_ij <- (sim_id - 1L) * n_iterations + j
    params <- params_sim  # Sampled once per sim_id
    params$seed <- seed_ij

    # Run model - handles ALL countries internally
    model <- lc$run_model(paramfile = params, quiet = TRUE)

    # Extract results for ALL countries
    likelihood <- calc_model_likelihood(
        obs_cases = params$reported_cases,    # All countries
        est_cases = model$results$expected_cases,  # All countries
        obs_deaths = params$reported_deaths,  # All countries
        est_deaths = model$results$disease_deaths  # All countries
    )
}
```

**Key Point**: Each `sim_id` samples different mobility parameters (τ_i, γ, ω) but runs the entire coupled system independently.

---

## Why All Distributed Frameworks Are Compatible

### Embarrassingly Parallel Property

```
BFRS Iteration Properties:
✅ Each simulation is INDEPENDENT
✅ No communication between simulations
✅ No shared state between simulations
✅ Results written to separate files
✅ Can be run in any order
✅ Can be restarted/resumed
✅ Failures don't affect other simulations

Multi-Country Coupling Properties:
✅ Happens INSIDE each simulation
✅ All countries advance together in lock-step
✅ Mobility/infection exchange handled by LASER Python code
✅ No inter-process communication needed
✅ Self-contained within single run_model() call
```

### Communication Pattern

```
❌ WRONG (would be incompatible with distributed computing):
┌────────────┐  exchange   ┌────────────┐  exchange   ┌────────────┐
│ Worker 1   │ ─────────→  │ Worker 2   │ ─────────→  │ Worker 3   │
│ (Ethiopia) │ ←───────────│ (Kenya)    │ ←───────────│ (Somalia)  │
└────────────┘  infection  └────────────┘  infection  └────────────┘
    ↑                                                         ↑
    └─────────────────────────────────────────────────────────┘

This would require MPI-style communication and lock-step execution.


✅ CORRECT (current MOSAIC architecture):
┌────────────────────────────────────────────────────────────┐
│ Worker 1: LASER(params₁) → [ETH ↔ KEN ↔ SOM] → results₁  │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│ Worker 2: LASER(params₂) → [ETH ↔ KEN ↔ SOM] → results₂  │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│ Worker 3: LASER(params₃) → [ETH ↔ KEN ↔ SOM] → results₃  │
└────────────────────────────────────────────────────────────┘

Each worker runs the FULL coupled system independently.
No inter-worker communication required!
```

---

## Distributed Framework Compatibility Matrix

| Framework | Compatible? | Notes |
|-----------|-------------|-------|
| **Dask** | ✅ YES | Perfect fit. Each task runs full multi-country LASER simulation |
| **Ray** | ✅ YES | Each remote function runs independent coupled simulation |
| **future.batchtools (Slurm)** | ✅ YES | Each Slurm job runs independent simulation |
| **Slurm Arrays** | ✅ YES | Each array task runs independent simulation |
| **GNU Parallel** | ✅ YES | Each parallel job runs independent simulation |
| **MPI** | ✅ YES (but overkill) | MPI communication not needed, but works |

### What WOULDN'T Work (Hypothetically)

If MOSAIC were designed like this (it's NOT):

```python
# ❌ WRONG ARCHITECTURE (not how MOSAIC works!)

# Simulation 1 runs ONLY Ethiopia
worker_1 = run_LASER_single_country(params, country="ETH")

# Simulation 2 runs ONLY Kenya
worker_2 = run_LASER_single_country(params, country="KEN")

# Need to exchange infection states between workers at each time step
for t in time_steps:
    # Worker 1 sends infections to Worker 2
    worker_2.receive_infections_from(worker_1, t)
    # Worker 2 sends infections to Worker 1
    worker_1.receive_infections_from(worker_2, t)

    worker_1.advance_one_step()
    worker_2.advance_one_step()
```

**This would require MPI-style communication and would NOT be compatible with Dask/Ray/Slurm arrays.**

But MOSAIC doesn't work this way! ✅

---

## Practical Implications

### 1. Dask Implementation (Recommended)

```python
# inst/python/dask_laser_runner.py

@dask.delayed
def run_coupled_simulation(sim_id, config_multi_country, priors):
    """
    Each Dask worker runs the FULL multi-country coupled system.

    config_multi_country contains:
    - location_name: ["ETH", "KEN", "SOM", ...]
    - mobility matrices between all pairs
    - initial conditions for all countries
    """
    from laser_cholera.metapop.model import run_model

    # Sample parameters (includes mobility params when multi-country)
    params = sample_from_priors(priors, seed=sim_id)

    # Run FULL coupled system (all countries together)
    model = run_model(paramfile=params, quiet=True)

    # Returns results for ALL countries
    return {
        'sim_id': sim_id,
        'cases_all_countries': model.results.expected_cases,
        'deaths_all_countries': model.results.disease_deaths
    }


def run_bfrs_distributed(sim_ids, config, priors, scheduler_address):
    client = Client(scheduler_address)

    # Each task is completely independent
    futures = [
        run_coupled_simulation(sim_id, config, priors)
        for sim_id in sim_ids
    ]

    results = client.gather(futures)
    return results
```

**Key Point**: Each Dask task runs the entire multi-country system. No inter-task communication needed!

### 2. Slurm Array Implementation

```bash
#!/bin/bash
#SBATCH --array=1-10000

# Each array task runs ONE independent multi-country simulation

Rscript -e "
  library(MOSAIC)

  # Multi-country config
  config <- get_location_config(iso = c('ETH', 'KEN', 'SOM'))
  priors <- get_location_priors(iso = c('ETH', 'KEN', 'SOM'))

  # Run single simulation (handles all 3 countries internally)
  result <- .mosaic_run_simulation_worker(
    sim_id = $SLURM_ARRAY_TASK_ID,
    config = config,  # Contains ALL 3 countries
    priors = priors,
    n_iterations = 3
  )
"
```

### 3. Future.batchtools Implementation

```r
library(future.batchtools)

# Setup Slurm backend
plan(batchtools_slurm, workers = 100)

# Multi-country config
config <- get_location_config(iso = c("ETH", "KEN", "SOM", "UGA"))
priors <- get_location_priors(iso = c("ETH", "KEN", "SOM", "UGA"))

# Each future runs the full 4-country coupled system
results <- future_lapply(1:10000, function(sim_id) {
    .mosaic_run_simulation_worker(
        sim_id = sim_id,
        config = config,  # All 4 countries
        priors = priors,
        n_iterations = 3
    )
})
```

---

## Performance Considerations

### Memory Requirements

**Per-worker memory scales with number of countries**:

```
Single country:  ~1-2 GB RAM per worker
5 countries:     ~3-5 GB RAM per worker
10 countries:    ~6-10 GB RAM per worker
40 countries:    ~20-40 GB RAM per worker (full SSA)
```

**Recommendation**: For large multi-country systems (>10 countries), use fewer workers per node with more memory each.

### Computational Scaling

```
Time per simulation ≈ O(n_countries² × n_timesteps)

Where:
- n_countries²: Mobility matrix is n×n
- n_timesteps: Usually ~365-3650 days (1-10 years)

Example (8-country East Africa):
- Single simulation: ~30-60 seconds
- 10,000 simulations: ~83-167 hours single-threaded
- With 100 workers: ~50-100 minutes (parallel)
```

### Optimal Configuration for Multi-Country

```r
# For 8-country East Africa model
control$parallel$n_cores <- 100  # Local: use all cores
# OR
control$parallel$n_nodes <- 10   # Dask/Slurm: 10 nodes
control$parallel$cores_per_node <- 120
control$parallel$memory_per_worker <- "5GB"  # Enough for 8 countries

# Each worker independently runs the full 8-country coupled system
```

---

## Testing Multi-Country Distribution

### Validation Checklist

- [ ] **Single country baseline**: Run with `iso="ETH"` (no mobility)
- [ ] **Two countries**: Run with `iso=c("ETH", "KEN")` (simple coupling)
- [ ] **Eight countries**: Run with East Africa (realistic coupling)
- [ ] **Sequential vs parallel**: Compare results (should be identical)
- [ ] **Local vs Dask**: Compare results (should be identical)
- [ ] **Resume from checkpoint**: Verify multi-country state preserved

### Test Script

```r
# Test: Multi-country distributed computing

library(MOSAIC)

# Multi-country config (East Africa)
iso_codes <- c("ETH", "KEN", "SOM", "UGA", "TZA", "SDN", "SSD", "RWA")
config <- get_location_config(iso = iso_codes)
priors <- get_location_priors(iso = iso_codes)

# Test 1: Sequential (baseline)
control_seq <- mosaic_control_defaults()
control_seq$parallel$enable <- FALSE
control_seq$calibration$n_simulations <- 100

results_seq <- run_MOSAIC(config, priors, control = control_seq)

# Test 2: Parallel (single node)
control_par <- mosaic_control_defaults()
control_par$parallel$enable <- TRUE
control_par$parallel$n_cores <- 10
control_par$calibration$n_simulations <- 100

results_par <- run_MOSAIC(config, priors, control = control_par)

# Test 3: Dask (distributed)
control_dask <- mosaic_control_defaults()
control_dask$parallel$backend <- "dask"
control_dask$parallel$scheduler_address <- "tcp://10.0.0.1:8786"
control_dask$calibration$n_simulations <- 100

results_dask <- run_MOSAIC_dask(config, priors, control = control_dask)

# Validate: All should give same parameter posteriors
compare_posteriors(results_seq, results_par, results_dask)
```

---

## Common Misconceptions

### ❌ Misconception 1: "Each worker needs to run a single country"

**Reality**: Each worker runs ALL countries as a coupled system. The coupling happens inside LASER.

### ❌ Misconception 2: "Workers need to communicate infection states"

**Reality**: No inter-worker communication. Each worker's LASER simulation handles all countries internally.

### ❌ Misconception 3: "MPI is required for multi-country models"

**Reality**: MPI is NOT needed. MOSAIC is embarrassingly parallel even with multi-country coupling.

### ❌ Misconception 4: "Distributed frameworks can't handle spatial coupling"

**Reality**: The spatial coupling is WITHIN each simulation, not BETWEEN simulations. Distributed frameworks work perfectly.

---

## Summary

### ✅ All Distributed Computing Frameworks Are Compatible

**Because**:
1. Multi-country coupling happens **inside** each LASER simulation
2. BFRS simulations are **independent** (embarrassingly parallel)
3. No inter-simulation communication required
4. Results written to separate files (no contention)

**Therefore**:
- ✅ Dask: Perfect fit (RECOMMENDED)
- ✅ Ray: Works great
- ✅ future.batchtools: Works with Slurm (IMPLEMENTED)
- ✅ Slurm Arrays: Simple and effective
- ✅ GNU Parallel: Quick prototyping

### Architecture Insight

```
┌──────────────────────────────────────────────────────────────┐
│ MOSAIC BFRS Calibration                                      │
│                                                              │
│ Parallel Dimension: Parameter space (different β, γ, τ...)  │
│ Sequential Dimension: Country coupling (handled by LASER)    │
│                                                              │
│ Each worker: params → LASER([Country1 ↔ Country2 ↔ ...])   │
└──────────────────────────────────────────────────────────────┘
```

**Result**: Scale to 100+ compute nodes with NO architectural changes needed!

---

## References

- LASER cholera documentation: https://docs.idmod.org/projects/laser-cholera/
- MOSAIC documentation: https://institutefordiseasemodeling.github.io/MOSAIC-docs/
- Metapopulation models: [Comparing metapopulation dynamics under different models of human movement (PNAS)](https://www.pnas.org/doi/10.1073/pnas.2007488118)
