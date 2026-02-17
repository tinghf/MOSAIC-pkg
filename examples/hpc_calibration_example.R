#!/usr/bin/env Rscript

# ==============================================================================
# MOSAIC Slurm HPC Calibration Example
# ==============================================================================
#
# This script demonstrates how to run a production-scale MOSAIC calibration
# on a Slurm HPC cluster using future.batchtools.
#
# Prerequisites:
#   1. Slurm HPC cluster
#   2. Shared filesystem accessible to all nodes
#   3. MOSAIC and future.batchtools installed
#   4. Python environment accessible on compute nodes
#
# Usage:
#   # Test first
#   Rscript tests/test_hpc_setup.R
#
#   # Then run this script
#   Rscript examples/hpc_calibration_example.R
#
# ==============================================================================

library(MOSAIC)

cat("====================================================================\n")
cat("MOSAIC Multi-Country Slurm HPC Calibration Example\n")
cat("====================================================================\n\n")

# ==============================================================================
# Configuration
# ==============================================================================

# Set MOSAIC root directory (MUST be on shared filesystem)
set_root_directory("~/MOSAIC")  # Adjust to your setup

# Output directory (will be created)
output_dir <- "~/MOSAIC/output/east_africa_hpc_demo"

# Multi-country configuration (East Africa)
iso_codes <- c("ETH", "KEN", "SOM", "UGA", "TZA", "SDN", "SSD", "RWA")

cat("Multi-country calibration:\n")
cat("  Countries:", paste(iso_codes, collapse = ", "), "\n")
cat("  Output:", output_dir, "\n\n")

# ==============================================================================
# Load Data
# ==============================================================================

cat("Loading configuration and priors...\n")

config <- get_location_config(iso = iso_codes)
priors <- get_location_priors(iso = iso_codes)

cat("  Locations:", length(config$location_name), "\n")
cat("  Time period:", config$date_start, "to", config$date_stop, "\n\n")

# ==============================================================================
# Slurm HPC Control Settings
# ==============================================================================

cat("Configuring Slurm HPC backend...\n")

# Verify Slurm is available
if (Sys.which("sbatch") == "") {
  stop("Slurm scheduler not detected. This script requires Slurm (sbatch command).")
}

cat("  ✓ Slurm scheduler detected\n")

# Create control structure
control <- mosaic_control_defaults(
  # ============================================================================
  # Calibration Strategy
  # ============================================================================
  calibration = list(
    n_simulations = 5000,       # Total simulations (adjust for test vs production)
    n_iterations = 3,           # LASER iterations per simulation
    max_simulations = 10000,    # Max total if using auto mode
    batch_size = 1000,          # Simulations per batch in auto mode
    target_r2 = 0.90            # R² convergence target
  ),

  # ============================================================================
  # Slurm Parallel Backend
  # ============================================================================
  parallel = list(
    enable = TRUE,
    type = "future",            # Use future.batchtools (Slurm)
    n_cores = 50,               # Number of Slurm jobs to launch

    # Slurm-specific settings
    backend = "slurm",
    template = NULL,            # NULL = use package default Slurm template

    # Resource requirements per job
    resources = list(
      nodes = 1,                # Nodes per job (always 1 for MOSAIC)
      cpus = 1,                 # CPUs per job (single-threaded workers)
      memory = "8GB",           # Memory for 8-country model
      walltime = "04:00:00",    # 4 hours max per job

      # Slurm-specific (adjust for your cluster)
      partition = "compute",    # Slurm partition name
      account = NULL            # Slurm account/project (optional)
    ),

    progress = TRUE             # Show progress (if progressr installed)
  ),

  # ============================================================================
  # Parameter Sampling
  # ============================================================================
  sampling = list(
    # Enable mobility sampling for multi-country
    sample_tau_i = TRUE,              # Travel probability
    sample_mobility_gamma = TRUE,     # Gravity model exponent
    sample_mobility_omega = TRUE,     # Mobility rate

    # All other parameters enabled by default
    sample_beta_j0_tot = TRUE,        # Transmission rate
    sample_gamma_1 = TRUE,            # Recovery rate
    sample_epsilon = TRUE,            # Immunity waning
    sample_mu_j = TRUE                # Case fatality ratio
  ),

  # ============================================================================
  # Likelihood Weighting
  # ============================================================================
  likelihood = list(
    weight_cases = 1.0,               # Weight for cases
    weight_deaths = 0.5,              # Weight for deaths (often less reliable)
    add_peak_timing = FALSE,          # Optional: penalize peak timing mismatch
    add_peak_magnitude = FALSE,       # Optional: penalize peak magnitude mismatch
    enable_guardrails = FALSE         # Optional: enable sanity checks
  ),

  # ============================================================================
  # Convergence Targets
  # ============================================================================
  targets = list(
    ESS_param = 500,                  # Effective sample size per parameter
    ESS_param_prop = 0.95,            # 95% of parameters must meet ESS target
    ESS_best = 300,                   # ESS for best subset
    A_best = 0.95,                    # Agreement index target
    CVw_best = 0.7,                   # Coefficient of variation
    min_best_subset = 30,             # Minimum best subset size
    max_best_subset = 1000            # Maximum best subset size
  ),

  # ============================================================================
  # Neural Posterior Estimation (Optional)
  # ============================================================================
  npe = list(
    enable = FALSE,                   # Disable for this demo (saves time)
    architecture_tier = "auto",       # "auto", "minimal", "small", "medium", "large"
    n_epochs = 1000,
    use_gpu = FALSE                   # Set TRUE if GPUs available
  ),

  # ============================================================================
  # Prediction Settings
  # ============================================================================
  predictions = list(
    best_model_n_sims = 100,          # Stochastic runs for best model
    ensemble_n_sims_per_param = 10    # Runs per parameter set in ensemble
  ),

  # ============================================================================
  # I/O Settings
  # ============================================================================
  io = list(
    format = "parquet",               # Binary format (fast, compressed)
    compression = "zstd",             # Compression algorithm
    compression_level = 5L,           # Balance speed vs size
    load_method = "streaming"         # Memory-safe loading
  ),

  # ============================================================================
  # Output Settings
  # ============================================================================
  paths = list(
    clean_output = FALSE,             # Don't delete existing output
    plots = TRUE                      # Generate diagnostic plots
  ),

  logging = list(
    verbose = FALSE                   # Detailed logging in sub-functions
  )
)

# ==============================================================================
# Validate Configuration
# ==============================================================================

cat("\nValidating configuration...\n")

# Check resource requirements
n_countries <- length(iso_codes)
memory_gb <- as.numeric(gsub("[^0-9.]", "", control$parallel$resources$memory))

cat("  Countries:", n_countries, "\n")
cat("  Memory per job:", control$parallel$resources$memory, "\n")
cat("  Workers:", control$parallel$n_cores, "\n")
cat("  Total simulations:", control$calibration$n_simulations, "\n")

# Estimate runtime
sims_per_worker <- ceiling(control$calibration$n_simulations / control$parallel$n_cores)
est_time_per_sim <- 60  # seconds (rough estimate for 8-country model)
est_total_time_min <- (sims_per_worker * control$calibration$n_iterations * est_time_per_sim) / 60

cat(sprintf("  Estimated runtime: %.1f minutes (%.1f hours)\n",
            est_total_time_min, est_total_time_min / 60))

# Memory check
recommended_memory <- 1 + (n_countries * 0.5)  # GB
if (memory_gb < recommended_memory) {
  cat(sprintf("  ⚠ Warning: Memory may be insufficient for %d countries\n", n_countries))
  cat(sprintf("    Recommended: %.1f GB, configured: %.1f GB\n",
              recommended_memory, memory_gb))
}

cat("\n")

# ==============================================================================
# Launch Calibration
# ==============================================================================

cat("====================================================================\n")
cat("Launching Slurm HPC calibration...\n")
cat("====================================================================\n\n")

cat("This will:\n")
cat("  1. Submit", control$parallel$n_cores, "jobs to Slurm scheduler\n")
cat("  2. Each job runs", sims_per_worker, "simulations\n")
cat("  3. Results written to shared filesystem\n")
cat("  4. Automatically combined when complete\n\n")

cat("Monitor progress:\n")
cat("  squeue -u $USER | grep MOSAIC\n")
cat("\n")

cat("Press Enter to continue, or Ctrl+C to cancel...\n")
readline()

# Run calibration
start_time <- Sys.time()

results <- tryCatch({
  run_MOSAIC(
    config = config,
    priors = priors,
    dir_output = output_dir,
    control = control,
    resume = FALSE  # Set TRUE to resume interrupted run
  )
}, error = function(e) {
  cat("\n✗ Calibration failed:\n")
  cat("  ", e$message, "\n\n")
  cat("Troubleshooting:\n")
  cat("  1. Check job logs: ls ~/.batchtools.logs/\n")
  cat("  2. Verify nodes can access shared filesystem\n")
  cat("  3. Test Python environment: Rscript tests/test_hpc_setup.R\n")
  quit(status = 1)
})

end_time <- Sys.time()
runtime <- as.numeric(difftime(end_time, start_time, units = "mins"))

# ==============================================================================
# Results Summary
# ==============================================================================

cat("\n====================================================================\n")
cat("✓ Calibration Complete\n")
cat("====================================================================\n\n")

cat(sprintf("Runtime: %.1f minutes (%.2f hours)\n", runtime, runtime / 60))
cat("Output directory:", output_dir, "\n\n")

cat("Key outputs:\n")
cat("  - Simulations:      1_bfrs/outputs/simulations.parquet\n")
cat("  - Posterior:        1_bfrs/posterior/posterior_quantiles.csv\n")
cat("  - Diagnostics:      1_bfrs/diagnostics/\n")
cat("  - Plots:            1_bfrs/plots/\n\n")

if (!is.null(results$summary)) {
  cat("Summary:\n")
  cat(sprintf("  Total simulations: %d\n", results$summary$sims_total))
  cat(sprintf("  Successful: %d (%.1f%%)\n",
              results$summary$sims_success,
              100 * results$summary$sims_success / results$summary$sims_total))
  cat(sprintf("  Converged: %s\n", if (results$summary$converged) "Yes" else "No"))
}

cat("\nNext steps:\n")
cat("  1. Review convergence diagnostics\n")
cat("  2. Examine posterior distributions\n")
cat("  3. Run NPE for fast posterior sampling (optional)\n")
cat("  4. Generate predictions with best parameters\n\n")

cat("====================================================================\n")
