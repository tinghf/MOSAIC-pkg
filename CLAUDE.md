# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Last Updated**: 2026-02-13
**Primary Sources**: README.md, DESCRIPTION, .github/workflows/R-CMD-check.yaml, NEWS.md, inst/py/environment.yml
**External Documentation**: https://institutefordiseasemodeling.github.io/MOSAIC-docs/

> **For Claude Code Instances**: When users ask about MOSAIC concepts, workflows, or scientific background that isn't covered in this file, use the WebFetch tool to consult the [MOSAIC documentation](https://institutefordiseasemodeling.github.io/MOSAIC-docs/). Key pages: Model Description, Data Sources, Parameter Estimation, Calibration Methods.

> **Maintenance Note**: When README.md, DESCRIPTION, or GitHub workflows are significantly updated, review and update this file accordingly. Key sections to check: project structure, dependencies, installation commands.

## Overview

MOSAIC (Metapopulation Outbreak Simulation with Agent-based Implementation for Cholera) is an R package that simulates cholera transmission dynamics in Sub-Saharan Africa using a metapopulation model with Bayesian calibration. The package wraps the Python-based **LASER-cholera** model and provides tools for parameter estimation, environmental forcing (climate data), mobility patterns, and intervention scenarios (vaccination).

## Quick Start

### Getting Started with MOSAIC on a VM

**Recommended Development Environment**: Starsim Hedgehog Server
- Access at: http://selfserve.starsim.org/
- Provides bare Ubuntu environment from Azure (Standard_HB120rs_v2 (HPC optimized - 120 cores, 456GB)

**Automated Setup**:
```bash
# Run the setup script to install all Python and R dependencies
bash vm/setup_mosaic.sh
```

This script ([vm/setup_mosaic.sh](https://github.com/InstituteforDiseaseModeling/MOSAIC-pkg/blob/main/vm/setup_mosaic.sh)) handles:
- System dependency installation (Ubuntu packages)
- R package installation
- Conda environment creation with Python dependencies
- Environment configuration

**Running Your First Model**:

After setup completes, you can run MOSAIC simulations:

1. **Toy Examples** (recommended for first-time users):
   - [Running LASER](https://institutefordiseasemodeling.github.io/MOSAIC-pkg/articles/Running-LASER.html) - Simple simulation with LASER engine
   - [Running MOSAIC](https://institutefordiseasemodeling.github.io/MOSAIC-pkg/articles/Running-MOSAIC.html) - Basic BFRS calibration workflow

2. **Substantial Example**:
   - Full model run script: [vm/launch_mosaic.R](https://github.com/InstituteforDiseaseModeling/MOSAIC-pkg/blob/main/vm/launch_mosaic.R)
   - Demonstrates real-world calibration with multiple countries/regions

**Troubleshooting Setup**:
- If setup fails with "'lib' is not writable" error, see the workaround in the [Package Installation and Setup](#package-installation-and-setup) section below
- Verify successful installation with `Rscript -e 'MOSAIC::check_dependencies()'`

## Common Development Commands

### Package Installation and Setup

```r
# Install system dependencies (Linux/macOS)
bash inst/bin/setup_mosaic.sh

# If setup_mosaic.sh fails installing R packages with a
# "'lib' is not writable" error, create a user library first:
#   mkdir -p ~/R/library
#   echo 'R_LIBS_USER=~/R/library' >> ~/.Renviron
# Then re-run the script.

# Install R package from source
R CMD INSTALL .

# Install Python dependencies (creates conda environment)
Rscript -e 'MOSAIC::install_dependencies(force=TRUE)'

# Verify dependencies
Rscript -e 'MOSAIC::check_dependencies()'
```

### Building and Testing

```r
# Build package tarball
R CMD build . --no-manual

# Check package (standard R CMD check)
R CMD check MOSAIC_*.tar.gz

# Run tests with testthat
Rscript -e 'devtools::test()'

# Run specific test file
Rscript -e 'testthat::test_file("tests/testthat/test-calc_model_likelihood.R")'

# Load package for interactive development
Rscript -e 'devtools::load_all()'
```

### Documentation

```r
# Build roxygen documentation
Rscript -e 'devtools::document()'

# Build pkgdown site
Rscript -e 'pkgdown::build_site()'
```

## High-Level Architecture

### Multi-Repository Structure

MOSAIC operates across three GitHub repositories:

```
MOSAIC/                          # Local parent directory
├── MOSAIC-pkg/                  # This repo - R package code
│   ├── R/                       # R functions
│   ├── inst/python/             # Python backend (NPE)
│   ├── inst/py/                 # Python environment spec
│   └── model/
│       ├── input/               # LASER input files (CSV matrices)
│       ├── output/              # Calibration results
│       └── LAUNCH.R             # Main workflow script
├── MOSAIC-data/                 # Data repo (separate)
│   ├── raw/                     # WHO, WorldPop, climate data
│   └── processed/               # Cleaned data for LASER
└── MOSAIC-docs/                 # Documentation website
    ├── figures/                 # Generated plots
    └── tables/                  # Parameter tables
```

### Core Components

**1. LASER-cholera (Python simulation engine)**
- Agent-based metapopulation cholera transmission model
- Accessed via `reticulate` from R (`run_LASER()` in [R/run_LASER.R](R/run_LASER.R))
- Takes parameter vectors and returns simulated cases/deaths time series
- Key parameters: transmission rate (β), recovery (γ), environmental suitability (ψ), mobility (π), vaccination coverage (φ), reporting rate (σ)

**2. BFRS Calibration (Bayesian Filtering with Resampling)**
- Sequential Monte Carlo approach to fit LASER to observed data
- Implemented in `run_MOSAIC()` ([R/run_MOSAIC.R](R/run_MOSAIC.R), 2000+ lines)
- Workflow:
  1. Sample parameters from priors
  2. Run LASER simulations in parallel
  3. Compute likelihoods against observed data ([R/calc_model_likelihood.R](R/calc_model_likelihood.R))
  4. Update parameter weights using Gibbs sampler
  5. Repeat until convergence (ESS, R², agreement metrics)
- Outputs: Weighted parameter samples in `model/output/1_bfrs/outputs/simulations.parquet`

**3. NPE (Neural Posterior Estimation)**
- Deep learning approach to approximate Bayesian posteriors using normalizing flows
- Trains a neural network to map observations → parameter distributions
- Python backend: [inst/python/npe_backend_v5_2.py](inst/python/npe_backend_v5_2.py) (PyTorch + Zuko library)
- R interface: [R/run_NPE.R](R/run_NPE.R), [R/npe.R](R/npe.R), [R/npe_posterior.R](R/npe_posterior.R)
- Architecture:
  - **Encoder**: EnhancedSpatialEncoder (TCN + multi-head attention) processes time series observations
  - **Flow**: Neural Spline Flow (NSF) with 10-20 transforms maps encoded observations to parameter posteriors
  - **Training**: Mixed-precision (AMP), gradient clipping, learning rate scheduling, early stopping
- Enables fast posterior sampling after expensive BFRS calibration

**4. Likelihood Function**
- Negative Binomial model for time series: `NB(observed | expected, overdispersion)`
- Additional penalty terms for:
  - Peak timing mismatch (Gaussian penalty)
  - Peak magnitude ratio (log-normal penalty)
  - Cumulative case/death totals (NB penalty)
- Guardrails prevent degenerate fits (see [R/calc_model_likelihood.R](R/calc_model_likelihood.R))

### Data Flow

```
User Configuration (get_location_config)
    ↓
Priors (get_location_priors)
    ↓
run_MOSAIC() ──→ BFRS Calibration
    │               ├─ sample_parameters() from priors
    │               ├─ run_LASER() (parallel workers)
    │               ├─ calc_model_likelihood()
    │               ├─ calc_model_weights_gibbs()
    │               └─ Check convergence
    ↓
Weighted samples → model/output/1_bfrs/outputs/simulations.parquet
    ↓
run_NPE() ──────→ Neural Training
    │               ├─ prepare_npe_data()
    │               ├─ train_npe() [R wrapper]
    │               └─ train_npe_v5_2() [Python backend]
    ↓
Trained model → model/output/2_npe/trained_model/npe_state.pt
    ↓
estimate_npe_posterior() ──→ Fast sampling for predictions
```

## Critical Considerations

### Threading and Parallelization

**IMPORTANT**: MOSAIC uses both R parallel execution and Python libraries (PyTorch, Numba) that have conflicting threading models. Failure to manage this causes segfaults, hangs, or "fork from non-main thread" errors.

**Thread management locations**:
1. **Package initialization** ([R/zzz.R](R/zzz.R)):
   - `.onLoad()` sets global environment variables BEFORE Python is initialized:
     - `OMP_NUM_THREADS=1`, `MKL_NUM_THREADS=1`, `NUMBA_NUM_THREADS=1`, `TBB_NUM_THREADS=1`
     - `KMP_DUPLICATE_LIB_OK=TRUE` (allows multiple OpenMP libraries)
     - `R_DATATABLE_NUM_THREADS=1` (prevents data.table segfaults)

2. **Before parallel cluster creation** (in multiple files):
   - Set threading environment variables again before `parallel::makeCluster()`
   - Call `RhpcBLASctl::blas_set_num_threads(1)` in each worker
   - Applies to: [R/run_MOSAIC.R](R/run_MOSAIC.R), [R/plot_model_fit_stochastic_param.R](R/plot_model_fit_stochastic_param.R), [R/plot_model_fit_stochastic.R](R/plot_model_fit_stochastic.R), [R/calc_npe_diagnostics.R](R/calc_npe_diagnostics.R)

**When modifying parallel code**: Always set threading limits BEFORE cluster creation AND in each worker initialization.

### Python Environment Management

- MOSAIC uses a conda environment named `mosaic-conda-env` (see [inst/py/environment.yml](inst/py/environment.yml))
- Key Python packages:
  - `laser-cholera==0.9.1` (cholera simulation engine)
  - `pytorch==2.1.2` (neural networks)
  - `sbi==0.22.0`, `lampe==0.9.0`, `zuko==1.3.0` (normalizing flows for NPE)
  - `tensorflow==2.15.0`, `keras==2.15.0` (optional, for suitability estimation)
- Python is initialized in `.onAttach()` ([R/zzz.R](R/zzz.R)) using `reticulate`
- Use `MOSAIC::attach_mosaic_env()` to manually activate the environment

### Configuration System

MOSAIC uses a complex nested list structure for configuration (`mosaic_control`):

```r
control <- list(
  calibration = list(n_simulations, batch_size, target_r2, ...),
  sampling = list(beta, gamma, epsilon, ...),  # 34 boolean flags
  likelihood = list(weight_cases, weight_deaths, ...),
  targets = list(ess_threshold, agreement_threshold, ...),
  npe = list(enable, architecture_tier, epochs, ...),
  parallel = list(enable, n_cores, type),
  io = list(format, compression)
)
```

- Defaults: [R/config_default.R](R/config_default.R) (`config_default` object)
- Validation/merging: [R/run_MOSAIC_helpers.R](R/run_MOSAIC_helpers.R) (`.mosaic_validate_and_merge_control()`)
- Epidemic/endemic presets: [R/config_simulation_epidemic.R](R/config_simulation_epidemic.R), [R/config_simulation_endemic.R](R/config_simulation_endemic.R)

### Output Directory Structure

```
model/output/
├── 0_setup/                     # Initial configuration
│   ├── config.json              # Full LASER config
│   └── priors.json              # Parameter priors
├── 1_bfrs/                      # BFRS calibration
│   ├── batch_*/                 # Per-batch outputs
│   │   ├── config/              # Parameter configs (one per sim)
│   │   ├── results/             # LASER outputs (HDF5/CSV)
│   │   └── likelihoods.csv      # Likelihood values
│   ├── diagnostics/             # Convergence plots
│   └── outputs/
│       └── simulations.parquet  # Final weighted samples
├── 2_npe/                       # Neural Posterior Estimation
│   ├── trained_model/
│   │   ├── npe_state.pt         # PyTorch model checkpoint
│   │   └── metadata.json        # Training metadata
│   ├── diagnostics/             # SBC, coverage, loss curves
│   └── posterior_samples.csv    # NPE-sampled parameters
└── 3_predictions/               # Forecast scenarios
```

## Key Files by Function

**Calibration & Inference**:
- [R/run_MOSAIC.R](R/run_MOSAIC.R) - Main BFRS calibration orchestrator
- [R/run_LASER.R](R/run_LASER.R) - Python wrapper for LASER simulations
- [R/run_NPE.R](R/run_NPE.R) - NPE workflow orchestrator
- [R/npe.R](R/npe.R) - NPE training (R interface)
- [R/npe_posterior.R](R/npe_posterior.R) - NPE sampling functions
- [R/calc_model_likelihood.R](R/calc_model_likelihood.R) - Likelihood computation
- [R/calc_model_weights_gibbs.R](R/calc_model_weights_gibbs.R) - SMC weight updates
- [R/sample_parameters.R](R/sample_parameters.R) - Parameter sampling from priors/weights

**Configuration & Setup**:
- [R/get_location_config.R](R/get_location_config.R) - Build LASER config from data
- [R/get_location_priors.R](R/get_location_priors.R) - Parameter prior distributions
- [R/make_LASER_config.R](R/make_LASER_config.R) - Config file generation
- [R/config_default.R](R/config_default.R) - Default control parameters

**Diagnostics**:
- [R/calc_convergence_diagnostics.R](R/calc_convergence_diagnostics.R) - ESS, R², agreement
- [R/calc_npe_diagnostics.R](R/calc_npe_diagnostics.R) - SBC, coverage, rank statistics
- [R/plot_model_fit.R](R/plot_model_fit.R) - Visualize fits to observed data
- [R/plot_model_parameters.R](R/plot_model_parameters.R) - Parameter distributions

**Infrastructure**:
- [R/zzz.R](R/zzz.R) - Package initialization, threading guards, Python environment setup
- [R/run_MOSAIC_infrastructure.R](R/run_MOSAIC_infrastructure.R) - Cluster deployment, state management
- [R/run_MOSAIC_helpers.R](R/run_MOSAIC_helpers.R) - Control validation, I/O utilities
- [R/check_dependencies.R](R/check_dependencies.R) - Dependency verification

**Data Processing** (90+ R files in [R/](R/)):
- `download_*.R` - Data acquisition (WHO, climate, shapefiles)
- `est_*.R` - A priori parameter estimation (mobility, suitability, seasonality, CFR)
- `process_*.R` - Data cleaning and aggregation
- `get_*.R` - Data retrieval helpers

## Testing Strategy

Tests use `testthat` (see [tests/testthat/](tests/testthat/)):

- **Unit tests**: Individual functions (e.g., `test-calc_model_likelihood.R`)
- **Integration tests**: NPE v5.2 training (`test-npe_v5_2.R`)
- **Estimation tests**: Initial conditions (`test-est_initial_E_I.R`), vaccination (`test-est_initial_V1_V2.R`)
- **Parallel tests**: Multi-core estimation (`test-est_initial_R_parallel.R`)

**Run tests before committing changes to core calibration/likelihood code.**

## Version History Notes

Recent versions have focused on stability:

- **v0.13.20-21**: Fixed Numba/TBB threading conflicts in ALL parallel contexts (eliminated hangs)
- **v0.13.3-4**: Improved NPE error handling (NA/NaN validation, clear error messages)
- **v0.13.5**: Linear interpolation for missing data (previously set to 0)

See [NEWS.md](NEWS.md) for detailed version history with bug fixes and rationale.

## Common Patterns

### Adding a new sampled parameter

1. Add to `config_default$sampling` in [R/config_default.R](R/config_default.R) (default: FALSE)
2. Add prior distribution in [R/get_location_priors.R](R/get_location_priors.R)
3. Add sampling logic in [R/sample_parameters.R](R/sample_parameters.R)
4. Update parameter extraction in [R/get_param_names.R](R/get_param_names.R)
5. Ensure LASER config accepts the parameter in [R/make_LASER_config.R](R/make_LASER_config.R)

### Modifying the likelihood function

Edit [R/calc_model_likelihood.R](R/calc_model_likelihood.R):
- Toggle likelihood components with `control$likelihood$use_*` flags
- Weight components with `control$likelihood$weight_*` values
- Add guardrails for degenerate fits (see `check_likelihood_guardrails()`)
- Run `testthat::test_file("tests/testthat/test-calc_model_likelihood.R")` after changes

### Creating a new NPE architecture

1. Modify [inst/python/npe_backend_v5_2.py](inst/python/npe_backend_v5_2.py):
   - Update `EnhancedSpatialEncoder` (TCN/attention layers)
   - Adjust `build_enhanced_nsf()` (number of transforms, spline bins)
2. Add architecture tier to `control$npe$architecture_tier` in [R/config_default.R](R/config_default.R)
3. Update auto-tuning logic in [R/npe.R](R/npe.R) (`train_npe()`)
4. Test with `testthat::test_file("tests/testthat/test-npe_v5_2.R")`

## Resources

- **Documentation**: https://institutefordiseasemodeling.github.io/MOSAIC-docs/
- **Package reference**: https://institutefordiseasemodeling.github.io/MOSAIC-pkg/
- **Issues**: https://github.com/InstituteforDiseaseModeling/MOSAIC-pkg/issues
- **LASER-cholera repo**: https://github.com/InstituteforDiseaseModeling/laser-cholera

## Using External Documentation

The [MOSAIC documentation site](https://institutefordiseasemodeling.github.io/MOSAIC-docs/) is regularly updated and contains scientific background, modeling details, and workflow examples not covered in this file.

**For future Claude Code instances working on this repo:**

Use the WebFetch tool to consult the documentation when users ask about:

1. **Project Rationale and Background**
   - Why MOSAIC was created
   - Project scope and goals
   - Fetch: `https://institutefordiseasemodeling.github.io/MOSAIC-docs/rationale.html`

2. **Data Sources and Processing**
   - WHO cholera data
   - WorldPop demographics
   - OpenMeteo climate data
   - Fetch: `https://institutefordiseasemodeling.github.io/MOSAIC-docs/data.html`

3. **Model Description**
   - Cholera transmission dynamics
   - SEIR compartmental structure
   - Environmental forcing
   - Mobility and spatial coupling
   - Fetch: `https://institutefordiseasemodeling.github.io/MOSAIC-docs/model-description.html`

4. **Calibration Methodology**
   - BFRS algorithm details
   - NPE architecture rationale
   - Likelihood function components
   - Fetch: `https://institutefordiseasemodeling.github.io/MOSAIC-docs/model-calibration.html`

5. **Scenarios and Interventions**
   - Vaccination strategies
   - Climate change impacts
   - Outbreak forecasting
   - Fetch: `https://institutefordiseasemodeling.github.io/MOSAIC-docs/scenarios.html`

6. **Usage Instructions**
   - Workflow tutorials
   - Example applications
   - Fetch: `https://institutefordiseasemodeling.github.io/MOSAIC-docs/usage.html`

**Example usage:**
```
User: "Can you explain how MOSAIC handles seasonal forcing?"

Claude: Let me fetch the latest documentation on environmental forcing...
[Use WebFetch on the model description page]
Based on the documentation, MOSAIC implements seasonal forcing through...
```

**Note**: The documentation site is built from the separate MOSAIC-docs repo and may contain information more recent than this CLAUDE.md file.

---

## Maintaining This File

This section is for repository maintainers to keep CLAUDE.md synchronized with evolving documentation.

### When to Update CLAUDE.md

Check for needed updates when:
1. **Before major releases** - Ensure all information is current
2. **After updating README.md** - Especially installation instructions or project structure
3. **After dependency changes** - DESCRIPTION or inst/py/environment.yml modifications
4. **After workflow changes** - New or modified GitHub Actions
5. **After architecture changes** - Major refactoring documented in NEWS.md

### How to Check if Update Needed

Run the sync check script:
```bash
bash inst/bin/check_claude_md_sync.sh
```

This checks if source files (README.md, DESCRIPTION, etc.) have been modified more recently than CLAUDE.md.

### How to Update

**Option 1: Use Claude Code (Recommended)**
```bash
# In your terminal with Claude Code CLI
claude-code
# Then run: /init
```

**Option 2: Manual Review**
1. Review changes in source files: `git diff HEAD~5 README.md DESCRIPTION NEWS.md`
2. Update relevant sections in CLAUDE.md
3. Update the "Last Updated" date at the top
4. Run sync check to confirm: `bash inst/bin/check_claude_md_sync.sh`

### What to Focus On

Priority sections to review when source files change:
- **Overview** - If project scope changes
- **Common Development Commands** - If installation/build process changes
- **High-Level Architecture** - If major components are added/removed
- **Critical Considerations** - If new gotchas or requirements emerge
- **Version History Notes** - After releases (sync with NEWS.md)
