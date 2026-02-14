#!/usr/bin/env Rscript
# ==============================================================================
# MOSAIC Single Country Run - For Parallel Execution on Multiple Nodes
# ==============================================================================
# Usage: Rscript run_single_country.R <ISO_CODE>
# Example: Rscript run_single_country.R ETH
# ==============================================================================

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: Rscript run_single_country.R <ISO_CODE>\nExample: Rscript run_single_country.R ETH")
}

iso_code <- args[1]

# Set library path for VM user installation
.libPaths(c('~/R/library', .libPaths()))

# Load required packages
library(MOSAIC)
MOSAIC::attach_mosaic_env(silent = FALSE)

# Create country-specific output directory
dir_output <- path.expand(paste0("~/MOSAIC/output/", iso_code))
if (!dir.exists(dir_output)) dir.create(dir_output, recursive = TRUE)

set_root_directory("~/MOSAIC")

cat("==============================================================================\n")
cat("MOSAIC Calibration -", iso_code, "\n")
cat("==============================================================================\n")
cat("Start time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Output directory:", dir_output, "\n")
cat("Node:", Sys.info()["nodename"], "\n")
cat("==============================================================================\n\n")

start_time <- Sys.time()

# Get configuration and priors for single country
priors <- get_location_priors(iso = iso_code)
config <- get_location_config(iso = iso_code)

# Configure calibration settings
control <- mosaic_control_defaults()

control$calibration$n_simulations <- 1000
control$calibration$n_iterations <- 3
control$calibration$batch_size <- 1000
control$calibration$min_batches <- 5
control$calibration$max_batches <- 10
control$calibration$target_r2 <- 0.95

# Enable parallel processing (use all cores on this node)
control$parallel$enable <- TRUE
control$parallel$n_cores <- parallel::detectCores() - 1

control$targets$ESS_param <- 1000
control$targets$ESS_param_prop <- 0.95
control$targets$ess_method <- 'perplexity'

# NO mobility parameters for independent country runs
control$sampling$sample_tau_i <- FALSE
control$sampling$sample_mobility_gamma <- FALSE
control$sampling$sample_mobility_omega <- FALSE

control$likelihood$weight_cases <- 1
control$likelihood$weight_deaths <- 0.05

control$npe$enable <- FALSE
control$npe$architecture_tier <- 'minimal'

control$paths$clean_output <- TRUE
control$io <- mosaic_io_presets("fast")
control$logging$verbose <- TRUE

# Run MOSAIC
result <- run_MOSAIC(
  dir_output = dir_output,
  config = config,
  priors = priors,
  control = control,
  resume = TRUE
)

# Report completion
end_time <- Sys.time()
runtime <- difftime(end_time, start_time, units = "hours")

cat("\n==============================================================================\n")
cat("MOSAIC Calibration Complete -", iso_code, "\n")
cat("==============================================================================\n")
cat("End time:", format(end_time, "%Y-%m-%d %H:%M:%S"), "\n")
cat("Total runtime:", round(runtime, 2), "hours\n")
cat("Output directory:", dir_output, "\n")
cat("==============================================================================\n")
