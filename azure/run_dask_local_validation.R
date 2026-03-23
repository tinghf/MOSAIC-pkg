#!/usr/bin/env Rscript
# =============================================================================
# run_dask_local_validation.R
# =============================================================================
# Runs the same simulations through BOTH run_MOSAIC() (local R parallel) and
# run_MOSAIC_dask() (Dask/Coiled) with identical config, priors, control, and
# seeds. Both paths now write per-sim simresults_*.parquet files containing
# raw LASER output (expected_cases, disease_deaths) plus all sampled parameters.
#
# This script only RUNS the two legs. To COMPARE results, use:
#   Rscript azure/compare_validation_results.R <local_dir> <dask_dir>
#
# Requirements:
#   - MOSAIC package installed
#   - MOSAIC-data available at the expected root
#   - A Dask cluster (Coiled or local scheduler) for the Dask leg
#
# Usage:
#   Rscript azure/run_dask_local_validation.R
#
# Or from inside a Docker container:
#   Rscript /src/MOSAIC-pkg/azure/run_dask_local_validation.R
# =============================================================================

library(MOSAIC)

cat("=============================================================\n")
cat("  MOSAIC: Dask vs Local — Run Both Legs\n")
cat("=============================================================\n\n")

# =============================================================================
# CONFIGURATION — adjust these as needed
# =============================================================================

N_SIMS    <- 100L           # Number of simulations to compare
N_ITER    <- 3L            # Iterations per simulation
ISO       <- "ETH"         # Location (single-country for speed)

# Dask cluster spec (Coiled) — adjust to your environment
DASK_SPEC <- list(
  type                = "coiled",
  n_workers           = 5L,
  software            = "mosaic-acr-workers",
  vm_types            = c("Standard_D4s_v6"),
  scheduler_vm_types  = c("Standard_D4s_v6"),
  region              = "westus2",
  idle_timeout        = "30 minutes"
)

# Root directory auto-detection
ROOT_DIR <- if (dir.exists("/workspace/MOSAIC")) {
  "/workspace/MOSAIC"
} else {
  path.expand("~/MOSAIC")
}

# Output directory
BASE_OUTPUT <- if (dir.exists("/workspace/output")) {
  "/workspace/output"
} else {
  file.path(getwd(), "output")
}

run_stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")

# =============================================================================
# SHARED SETUP (identical for both legs)
# =============================================================================

set_root_directory(ROOT_DIR)
PATHS <- get_paths()

cat(sprintf("Root:       %s\n", ROOT_DIR))
cat(sprintf("Location:   %s\n", ISO))
cat(sprintf("Sims:       %d  (sim_ids 1:%d)\n", N_SIMS, N_SIMS))
cat(sprintf("Iterations: %d per sim\n", N_ITER))
cat(sprintf("Output:     %s\n\n", BASE_OUTPUT))

config <- get_location_config(iso = ISO)
priors <- get_location_priors(iso = ISO)

# Build a minimal control — identical for both legs
ctrl <- mosaic_control_defaults(
  calibration = list(
    n_simulations  = N_SIMS,     # fixed mode
    n_iterations   = N_ITER,
    batch_size     = N_SIMS      # single batch
  ),
  parallel = list(
    enable  = TRUE,              # must be parallel: .mosaic_run_simulation_worker()
    n_cores = 8L,                # references `control` as free var, only available
    type    = "PSOCK",           # in workers via clusterExport (not in sequential mode)
    progress = TRUE
  ),
  npe   = list(enable = FALSE),
  paths = list(
    clean_output = TRUE,
    plots        = FALSE         # skip plots for speed
  ),
  io = c(mosaic_io_presets("fast"), save_simresults = TRUE)
)

# =============================================================================
# LEG 1: run_MOSAIC (local, parallel)
# =============================================================================

dir_local <- file.path(BASE_OUTPUT, paste0("validate_local_", run_stamp))

cat("-------------------------------------------------------------\n")
cat("LEG 1: run_MOSAIC (local, parallel)\n")
cat(sprintf("  Output -> %s\n", dir_local))
cat("-------------------------------------------------------------\n")

t_local_start <- Sys.time()

# Wrap in tryCatch — post-processing may fail with small N but
# simulation_results parquets are written before that stage
result_local <- tryCatch(
  run_MOSAIC(
    config     = config,
    priors     = priors,
    dir_output = dir_local,
    control    = ctrl
  ),
  error = function(e) {
    cat(sprintf("\n  NOTE: run_MOSAIC post-processing error (non-fatal):\n    %s\n", e$message))
    cat("  simulation_results parquets should still be available.\n\n")
    NULL
  }
)

t_local <- as.numeric(difftime(Sys.time(), t_local_start, units = "secs"))
cat(sprintf("\nLeg 1 complete: %.1fs\n\n", t_local))

# Verify simulation_results dir exists
local_simresults_dir <- file.path(dir_local, "1_bfrs", "outputs", "simulation_results")
local_n_files <- length(list.files(local_simresults_dir, pattern = "\\.parquet$"))
if (local_n_files == 0) {
  stop("No simulation_results parquets found in: ", local_simresults_dir,
       "\n  run_MOSAIC failed before writing simulation results.")
}
cat(sprintf("  Local simulation_results: %d parquet files\n", local_n_files))

# =============================================================================
# LEG 2: run_MOSAIC_dask (Dask cluster)
# =============================================================================

dir_dask <- file.path(BASE_OUTPUT, paste0("validate_dask_", run_stamp))

cat("\n-------------------------------------------------------------\n")
cat("LEG 2: run_MOSAIC_dask (Dask cluster)\n")
cat(sprintf("  Output -> %s\n", dir_dask))
cat("-------------------------------------------------------------\n")

t_dask_start <- Sys.time()

result_dask <- tryCatch(
  run_MOSAIC_dask(
    config     = config,
    priors     = priors,
    dir_output = dir_dask,
    control    = ctrl,
    dask_spec  = DASK_SPEC
  ),
  error = function(e) {
    cat(sprintf("\n  NOTE: run_MOSAIC_dask post-processing error (non-fatal):\n    %s\n", e$message))
    cat("  simulation_results parquets should still be available.\n\n")
    NULL
  }
)

t_dask <- as.numeric(difftime(Sys.time(), t_dask_start, units = "secs"))
cat(sprintf("\nLeg 2 complete: %.1fs\n\n", t_dask))

# Verify simulation_results dir exists
dask_simresults_dir <- file.path(dir_dask, "1_bfrs", "outputs", "simulation_results")
dask_n_files <- length(list.files(dask_simresults_dir, pattern = "\\.parquet$"))
if (dask_n_files == 0) {
  stop("No simulation_results parquets found in: ", dask_simresults_dir,
       "\n  run_MOSAIC_dask failed before writing simulation results.")
}
cat(sprintf("  Dask simulation_results: %d parquet files\n", dask_n_files))

# =============================================================================
# DONE — prompt user to compare
# =============================================================================

cat("\n=============================================================\n")
cat("  BOTH LEGS COMPLETE\n")
cat("=============================================================\n\n")
cat(sprintf("  Timing: local=%.1fs  dask=%.1fs\n\n", t_local, t_dask))
cat(sprintf("  Local output: %s\n", dir_local))
cat(sprintf("  Dask  output: %s\n\n", dir_dask))
cat("To compare results, run:\n\n")
cat(sprintf("  Rscript azure/compare_validation_results.R \\\n    %s \\\n    %s\n",
            dir_local, dir_dask))
cat("\n=============================================================\n")
