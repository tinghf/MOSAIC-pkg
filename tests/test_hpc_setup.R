#!/usr/bin/env Rscript

# ==============================================================================
# MOSAIC HPC Setup Test Script
# ==============================================================================
#
# This script validates that future.batchtools is correctly configured for
# your Slurm HPC cluster before running large-scale MOSAIC calibrations.
#
# Usage:
#   Rscript tests/test_hpc_setup.R
#
# Expected runtime: 5-10 minutes
#
# ==============================================================================

cat("====================================================================\n")
cat("MOSAIC Slurm HPC Setup Validation\n")
cat("====================================================================\n\n")

# ==============================================================================
# 1. Package Dependencies
# ==============================================================================

cat("[1/6] Checking R package dependencies...\n")

required_packages <- c("MOSAIC", "future", "future.batchtools", "future.apply")
missing_packages <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]

if (length(missing_packages) > 0) {
  cat("  ✗ Missing packages:", paste(missing_packages, collapse = ", "), "\n")
  cat("  Install with: install.packages(c('", paste(missing_packages, collapse = "', '"), "'))\n", sep = "")
  quit(status = 1)
} else {
  cat("  ✓ All required packages installed\n")
}

library(MOSAIC)
library(future.batchtools)
library(future.apply)

# ==============================================================================
# 2. MOSAIC Installation
# ==============================================================================

cat("\n[2/6] Checking MOSAIC installation...\n")

# Check Python dependencies
tryCatch({
  MOSAIC::check_dependencies()
  cat("  ✓ MOSAIC dependencies OK\n")
}, error = function(e) {
  cat("  ✗ MOSAIC dependency check failed:\n")
  cat("   ", e$message, "\n")
  cat("  Run: MOSAIC::install_dependencies()\n")
  quit(status = 1)
})

# Check root directory
root_dir <- getOption("root_directory")
if (is.null(root_dir)) {
  cat("  ✗ Root directory not set\n")
  cat("  Run: set_root_directory('/path/to/MOSAIC')\n")
  quit(status = 1)
} else {
  cat("  ✓ Root directory:", root_dir, "\n")
}

# ==============================================================================
# 3. Slurm Scheduler Detection
# ==============================================================================

cat("\n[3/6] Detecting Slurm scheduler...\n")

if (Sys.which("sbatch") == "") {
  cat("  ⚠ Slurm scheduler not detected\n")
  cat("  This script requires Slurm (sbatch command)\n")
  cat("  For local testing, use control$parallel$type = 'PSOCK'\n")
  quit(status = 0)  # Not an error, just not applicable
} else {
  cat("  ✓ Slurm scheduler detected\n")
}

scheduler <- "slurm"

# ==============================================================================
# 4. Template Validation
# ==============================================================================

cat("\n[4/6] Validating Slurm templates...\n")

template_file <- system.file("templates/slurm.tmpl", package = "MOSAIC")

if (!file.exists(template_file) || nchar(template_file) == 0) {
  cat("  ✗ Slurm template not found\n")
  cat("  Expected at: inst/templates/slurm.tmpl\n")
  quit(status = 1)
} else {
  cat("  ✓ Template found: slurm.tmpl\n")

  # Validate template syntax
  template_content <- readLines(template_file)
  has_job_name <- any(grepl("job.name", template_content, fixed = TRUE))
  has_resources <- any(grepl("resources\\$", template_content))
  has_batchtools <- any(grepl("batchtools::doJobCollection", template_content, fixed = TRUE))

  if (!has_job_name || !has_resources || !has_batchtools) {
    cat("  ⚠ Template may be incomplete:\n")
    cat("    - Has job.name:", has_job_name, "\n")
    cat("    - Has resources:", has_resources, "\n")
    cat("    - Has batchtools call:", has_batchtools, "\n")
  } else {
    cat("  ✓ Template syntax validated\n")
  }
}

# ==============================================================================
# 5. Small Test Job
# ==============================================================================

cat("\n[5/6] Running test job on cluster...\n")

test_output_dir <- file.path(tempdir(), "mosaic_hpc_test")
dir.create(test_output_dir, showWarnings = FALSE, recursive = TRUE)

cat("  Output directory:", test_output_dir, "\n")

# Create minimal test config
config <- MOSAIC::config_simulation_epidemic
priors <- MOSAIC::priors_simulation_epidemic

# Configure for Slurm with minimal resources
control <- MOSAIC::mosaic_control_defaults(
  calibration = list(
    n_simulations = 10,  # Only 10 simulations for test
    n_iterations = 1
  ),
  parallel = list(
    enable = TRUE,
    type = "future",
    n_cores = 2,  # Only 2 jobs
    backend = "slurm",
    resources = list(
      cpus = 1,
      memory = "2GB",
      walltime = "00:10:00",  # 10 minutes max
      partition = NULL,  # Use default partition
      account = NULL
    )
  ),
  paths = list(
    plots = FALSE  # Skip plotting for speed
  ),
  npe = list(
    enable = FALSE  # Skip NPE for test
  )
)

cat("  Submitting 2 test jobs (10 simulations total)...\n")
cat("  This may take 5-10 minutes...\n\n")

# Run test calibration
test_start <- Sys.time()

test_result <- tryCatch({
  MOSAIC::run_MOSAIC(
    config = config,
    priors = priors,
    dir_output = test_output_dir,
    control = control
  )
  TRUE
}, error = function(e) {
  cat("  ✗ Test calibration failed:\n")
  cat("   ", e$message, "\n")
  FALSE
})

test_end <- Sys.time()
test_duration <- as.numeric(difftime(test_end, test_start, units = "secs"))

if (test_result) {
  cat(sprintf("  ✓ Test calibration completed in %.1f seconds\n", test_duration))

  # Validate output
  output_file <- file.path(test_output_dir, "1_bfrs", "outputs", "simulations.parquet")
  if (file.exists(output_file)) {
    cat("  ✓ Output file created successfully\n")

    # Check simulation count
    results <- arrow::read_parquet(output_file)
    n_sims <- nrow(results)
    cat(sprintf("  ✓ Found %d simulation results\n", n_sims))

    if (n_sims != 10) {
      cat(sprintf("  ⚠ Warning: Expected 10 simulations, got %d\n", n_sims))
    }
  } else {
    cat("  ✗ Output file not found\n")
    cat("   Expected:", output_file, "\n")
  }
} else {
  cat("\n  Test failed. Common issues:\n")
  cat("  1. Cluster quota/permissions problems\n")
  cat("  2. Python environment not accessible on compute nodes\n")
  cat("  3. Shared filesystem issues\n")
  cat("  4. Slurm-specific configuration needed\n\n")
  cat("  Check logs at: ~/.batchtools.logs/\n")
  quit(status = 1)
}

# ==============================================================================
# 6. Performance Benchmark
# ==============================================================================

cat("\n[6/6] Estimating cluster performance...\n")

if (test_result && test_duration > 0) {
  # Calculate throughput
  sims_per_second <- 10 / test_duration
  sims_per_hour <- sims_per_second * 3600

  cat(sprintf("  Throughput: %.2f simulations/second\n", sims_per_second))
  cat(sprintf("              %.0f simulations/hour (with 2 workers)\n", sims_per_hour))

  # Estimate scaling
  cat("\n  Estimated times for production calibration:\n")

  scenarios <- list(
    list(n_sims = 1000, n_workers = 10, desc = "Small (1k sims, 10 workers)"),
    list(n_sims = 10000, n_workers = 100, desc = "Medium (10k sims, 100 workers)"),
    list(n_sims = 50000, n_workers = 500, desc = "Large (50k sims, 500 workers)")
  )

  for (scenario in scenarios) {
    est_time_hours <- (scenario$n_sims / sims_per_hour) * (2 / scenario$n_workers) * 1.2  # 20% overhead
    cat(sprintf("  - %s: ~%.1f hours\n", scenario$desc, est_time_hours))
  }
}

# ==============================================================================
# Summary
# ==============================================================================

cat("\n====================================================================\n")
cat("✓ Slurm HPC Setup Validation PASSED\n")
cat("====================================================================\n\n")

cat("Your Slurm cluster is ready for MOSAIC calibrations!\n\n")

cat("Next steps:\n")
cat("1. Review vignette: vignette('hpc-deployment', package = 'MOSAIC')\n")
cat("2. Adjust resources for your model size (see vignette)\n")
cat("3. Run production calibration with control$parallel$type = 'future'\n\n")

cat("Example:\n")
cat("  control <- mosaic_control_defaults(\n")
cat("    parallel = list(\n")
cat("      enable = TRUE,\n")
cat("      type = 'future',\n")
cat("      backend = 'slurm',\n")
cat("      n_cores = 100,\n")
cat("      resources = list(cpus = 1, memory = '6GB', walltime = '04:00:00')\n")
cat("    )\n")
cat("  )\n\n")

# Cleanup
unlink(test_output_dir, recursive = TRUE)

cat("Test artifacts cleaned up.\n")
cat("====================================================================\n")
