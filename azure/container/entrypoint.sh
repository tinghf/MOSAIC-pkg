#!/bin/bash
# ==============================================================================
# MOSAIC Container Entrypoint
# ==============================================================================
# Configurable MOSAIC run script for containerized execution
#
# Environment Variables:
#   ISO_CODE           - Country code (default: SOM)
#   N_SIMULATIONS      - Number of simulations per batch (default: 1000)
#   N_ITERATIONS       - Number of BFRS iterations (default: 3)
#   N_CORES            - Parallel cores (default: auto-detect - 1)
#   TARGET_R2          - Target R² for convergence (default: 0.95)
#   ENABLE_NPE         - Enable NPE training (default: FALSE)
#   OUTPUT_DIR         - Output directory (default: /outputs)
#   COMPRESS_OUTPUT    - Create tar.gz archive (default: TRUE)
#
# ==============================================================================

set -e

# Configuration from environment variables
ISO_CODE="${ISO_CODE:-SOM}"
N_SIMULATIONS="${N_SIMULATIONS:-1000}"
N_ITERATIONS="${N_ITERATIONS:-3}"
N_CORES="${N_CORES:-$(($(nproc) - 1))}"
TARGET_R2="${TARGET_R2:-0.95}"
ENABLE_NPE="${ENABLE_NPE:-FALSE}"
OUTPUT_DIR="${OUTPUT_DIR:-/outputs}"
COMPRESS_OUTPUT="${COMPRESS_OUTPUT:-TRUE}"

echo "======================================"
echo "MOSAIC Containerized Run"
echo "======================================"
echo "ISO Code: $ISO_CODE"
echo "Simulations: $N_SIMULATIONS"
echo "Iterations: $N_ITERATIONS"
echo "Cores: $N_CORES"
echo "Target R²: $TARGET_R2"
echo "NPE: $ENABLE_NPE"
echo "Output: $OUTPUT_DIR"
echo "======================================"
echo "Start time: $(date)"
echo ""

# Create R script dynamically
cat > /tmp/run_mosaic.R <<EOF
# Set library path
.libPaths(c('/usr/local/lib/R/site-library', .libPaths()))

# Load MOSAIC
library(MOSAIC)
MOSAIC::attach_mosaic_env(silent = FALSE)

# Create output directory
dir_output <- file.path("${OUTPUT_DIR}", "${ISO_CODE}")
if (!dir.exists(dir_output)) dir.create(dir_output, recursive = TRUE)

set_root_directory("${OUTPUT_DIR}")

cat("\\n")
cat("Running MOSAIC for ${ISO_CODE}\\n")
cat("Output directory:", dir_output, "\\n")
cat("\\n")

start_time <- Sys.time()

# Get configuration
priors <- get_location_priors(iso="${ISO_CODE}")
config <- get_location_config(iso="${ISO_CODE}")

# Set control parameters
control <- mosaic_control_defaults()

control\$calibration\$n_simulations <- ${N_SIMULATIONS}
control\$calibration\$n_iterations <- ${N_ITERATIONS}
control\$calibration\$batch_size <- ${N_SIMULATIONS}
control\$calibration\$target_r2 <- ${TARGET_R2}

control\$parallel\$enable <- TRUE
control\$parallel\$n_cores <- ${N_CORES}

control\$targets\$ESS_param <- 1000
control\$targets\$ESS_param_prop <- 0.95

control\$likelihood\$weight_cases <- 1
control\$likelihood\$weight_deaths <- 0.05

control\$npe\$enable <- ${ENABLE_NPE}
control\$npe\$architecture_tier <- 'minimal'

control\$paths\$clean_output <- TRUE
control\$io <- mosaic_io_presets("fast")
control\$logging\$verbose <- TRUE

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

cat("\\n====================================\\n")
cat("MOSAIC Calibration Complete\\n")
cat("====================================\\n")
cat("Runtime:", round(runtime, 2), "hours\\n")
cat("====================================\\n")

# Return success
quit(status = 0)
EOF

# Run R script
Rscript /tmp/run_mosaic.R

EXIT_CODE=$?

# Compress output if requested
if [ "$COMPRESS_OUTPUT" = "TRUE" ] && [ $EXIT_CODE -eq 0 ]; then
  echo ""
  echo "Compressing output..."
  cd "${OUTPUT_DIR}"
  tar -czf "${ISO_CODE}.tar.gz" "${ISO_CODE}/"
  echo "Archive created: ${OUTPUT_DIR}/${ISO_CODE}.tar.gz"

  # Calculate sizes
  DIR_SIZE=$(du -sh "${ISO_CODE}" | cut -f1)
  TAR_SIZE=$(du -sh "${ISO_CODE}.tar.gz" | cut -f1)
  echo "Directory size: $DIR_SIZE"
  echo "Archive size: $TAR_SIZE"
fi

echo ""
echo "======================================"
echo "Container execution complete"
echo "======================================"
echo "End time: $(date)"
echo "Exit code: $EXIT_CODE"

exit $EXIT_CODE
