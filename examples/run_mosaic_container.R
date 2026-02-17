#!/usr/bin/env Rscript

# ============================================================================
# MOSAIC Containerized SLURM Deployment Example
# ============================================================================
#
# This script demonstrates running MOSAIC on SLURM using a Singularity/Apptainer
# container instead of direct installation. No setup required on cluster!
#
# Prerequisites:
#   1. Build container: singularity build mosaic_latest.sif inst/containers/mosaic.def
#   2. Copy to cluster: ~/containers/mosaic_latest.sif
#   3. Run this script: Rscript run_mosaic_container.R
#
# ============================================================================

library(MOSAIC)

# Set root directory
set_root_directory("~/MOSAIC")  # Update to your data location

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------

# Multi-country analysis
iso_codes <- c("ETH", "KEN", "SOM")

# Get location-specific configuration
config <- get_location_config(iso = iso_codes)
priors <- get_location_priors(iso = iso_codes)

# ----------------------------------------------------------------------------
# SLURM Container Configuration
# ----------------------------------------------------------------------------

control <- mosaic_control_defaults(
  calibration = list(
    n_simulations = 10000,
    n_iterations = 3,
    batch_size = 100
  ),

  parallel = list(
    enable = TRUE,
    type = "future",              # Enable HPC backend
    n_cores = 100,                # 100 SLURM jobs
    backend = "slurm",

    # KEY: Use container template
    template = system.file("templates/slurm-container.tmpl", package = "MOSAIC"),

    resources = list(
      cpus = 1,
      memory = "6GB",             # Adjust based on number of countries
      walltime = "04:00:00",      # 4 hours max

      # Update these for your cluster
      partition = "compute",      # ← YOUR PARTITION NAME
      account = NULL,             # ← YOUR ACCOUNT (if required)

      # CRITICAL: Path to container on cluster
      container_image = "~/containers/mosaic_latest.sif"  # ← UPDATE THIS PATH
    )
  ),

  npe = list(
    enable = TRUE,
    architecture_tier = "standard"
  )
)

# ----------------------------------------------------------------------------
# Run MOSAIC
# ----------------------------------------------------------------------------

cat("\n")
cat("========================================================================\n")
cat("MOSAIC Containerized SLURM Deployment\n")
cat("========================================================================\n")
cat("Countries:", paste(iso_codes, collapse = ", "), "\n")
cat("Workers:", control$parallel$n_cores, "\n")
cat("Container:", control$parallel$resources$container_image, "\n")
cat("Template:", basename(control$parallel$template), "\n")
cat("========================================================================\n")
cat("\n")

# Verify container exists
container_path <- path.expand(control$parallel$resources$container_image)
if (!file.exists(container_path)) {
  stop(
    "Container not found: ", container_path, "\n",
    "Build with: singularity build mosaic_latest.sif inst/containers/mosaic.def\n",
    "Or update control$parallel$resources$container_image path",
    call. = FALSE
  )
}

# Run calibration
output_dir <- "./output_container"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

results <- run_MOSAIC(
  config = config,
  priors = priors,
  dir_output = output_dir,
  control = control
)

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------

cat("\n")
cat("========================================================================\n")
cat("✓ Calibration Complete\n")
cat("========================================================================\n")
cat("Output directory:", output_dir, "\n")
cat("Results:", file.path(output_dir, "1_bfrs/outputs/simulations.parquet"), "\n")
cat("========================================================================\n")
