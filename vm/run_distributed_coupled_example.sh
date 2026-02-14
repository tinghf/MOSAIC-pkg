#!/bin/bash
# ==============================================================================
# Example: Distributed Coupled Multi-Country MOSAIC (Iterative Approach)
# ==============================================================================
# This script demonstrates running coupled country models across multiple
# compute nodes using the iterative offline coupling approach.
#
# Usage:
#   1. Edit the COUNTRIES, SHARED_DIR, and SLURM settings below
#   2. Submit: bash run_distributed_coupled_example.sh
#   3. Monitor progress in logs/coupling_iter_*/
# ==============================================================================

# Configuration
COUNTRIES=("ETH" "KEN" "SOM")
N_ITERATIONS=3
SHARED_DIR="/scratch/mosaic_coupled"
SLURM_PARTITION="compute"  # Adjust for your cluster
SLURM_TIME="12:00:00"
SLURM_CPUS=32
SLURM_MEM="64G"

# Create shared directories
mkdir -p ${SHARED_DIR}/{trajectories,output,logs,jobs}

echo "========================================"
echo "Distributed Coupled MOSAIC Calibration"
echo "========================================"
echo "Countries: ${COUNTRIES[@]}"
echo "Iterations: $N_ITERATIONS"
echo "Shared directory: $SHARED_DIR"
echo "========================================"
echo ""

# ==============================================================================
# Iterative Coupling Loop
# ==============================================================================

for ITER in $(seq 0 $N_ITERATIONS); do

  echo "========================================"
  echo "Iteration $ITER of $N_ITERATIONS"
  echo "========================================"

  # Create log directory for this iteration
  LOG_DIR="${SHARED_DIR}/logs/coupling_iter_$(printf '%03d' $ITER)"
  mkdir -p $LOG_DIR

  JOB_IDS=()

  # Submit job for each country
  for COUNTRY in "${COUNTRIES[@]}"; do

    echo "Submitting: $COUNTRY (iteration $ITER)"

    # Create SLURM job script
    JOB_SCRIPT="${SHARED_DIR}/jobs/${COUNTRY}_iter_$(printf '%03d' $ITER).sh"

    cat > $JOB_SCRIPT << EOF
#!/bin/bash
#SBATCH --job-name=mosaic_${COUNTRY}_i${ITER}
#SBATCH --output=${LOG_DIR}/${COUNTRY}.out
#SBATCH --error=${LOG_DIR}/${COUNTRY}.err
#SBATCH --partition=$SLURM_PARTITION
#SBATCH --nodes=1
#SBATCH --cpus-per-task=$SLURM_CPUS
#SBATCH --mem=$SLURM_MEM
#SBATCH --time=$SLURM_TIME

echo "=========================================="
echo "Country: $COUNTRY"
echo "Iteration: $ITER"
echo "Node: \$SLURMD_NODENAME"
echo "Start time: \$(date)"
echo "=========================================="

# Load modules (adjust for your cluster)
# module load R/4.3.0
# module load gcc/11.2.0

# Set threading limits
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export NUMBA_NUM_THREADS=1

# Run single country with coupling
Rscript -e "
library(MOSAIC)

iso <- '$COUNTRY'
iter <- $ITER
shared_dir <- '$SHARED_DIR'
all_countries <- c('${COUNTRIES[@]}')

cat('Loading configuration for', iso, '...\n')
config <- MOSAIC::get_location_config(iso = iso)
priors <- MOSAIC::get_location_priors(iso = iso)

# Control parameters
control <- MOSAIC::mosaic_control_defaults()
control\\\$calibration\\\$n_simulations <- 1000
control\\\$calibration\\\$n_iterations <- 3
control\\\$calibration\\\$batch_size <- 1000
control\\\$parallel\\\$enable <- TRUE
control\\\$parallel\\\$n_cores <- $SLURM_CPUS - 1
control\\\$sampling\\\$sample_tau_i <- TRUE
control\\\$sampling\\\$sample_mobility_gamma <- TRUE
control\\\$sampling\\\$sample_mobility_omega <- TRUE

# Add external forcing if iter > 0
if (iter > 0) {
  cat('Loading external trajectories from iteration', iter - 1, '...\n')

  external_trajs <- list()
  for (other_iso in setdiff(all_countries, iso)) {
    traj_file <- file.path(
      shared_dir,
      'trajectories',
      paste0(other_iso, '_iter', sprintf('%03d', iter - 1), '_trajectory.csv')
    )

    if (!file.exists(traj_file)) {
      stop('Missing trajectory: ', traj_file)
    }

    external_trajs[[other_iso]] <- read.csv(traj_file)
    cat('  Loaded:', other_iso, '(', nrow(external_trajs[[other_iso]]), 'time steps)\n')
  }

  # NOTE: Full implementation would inject external forcing here
  # For now, this serves as a template
  cat('  External forcing loaded (', length(external_trajs), 'countries)\n')
}

# Run MOSAIC
cat('Running MOSAIC calibration...\n')
country_output <- file.path(shared_dir, 'output', iso, sprintf('iter_%03d', iter))

result <- MOSAIC::run_MOSAIC(
  dir_output = country_output,
  config = config,
  priors = priors,
  control = control,
  resume = TRUE
)

cat('Calibration complete!\n')

# Extract trajectory (simplified)
# In production, this would extract median trajectory from calibrated ensemble
trajectory <- data.frame(
  date = seq(as.Date('2015-01-01'), as.Date('2024-12-31'), by = 'week'),
  location = iso,
  I1 = 0,  # Placeholder - extract from result
  I2 = 0
)

# Save trajectory for next iteration
traj_file <- file.path(
  shared_dir,
  'trajectories',
  paste0(iso, '_iter', sprintf('%03d', iter), '_trajectory.csv')
)

write.csv(trajectory, traj_file, row.names = FALSE)
cat('Saved trajectory:', traj_file, '\n')

cat('========================================\n')
cat('Completed:', iso, 'iteration', iter, '\n')
cat('End time:', format(Sys.time()), '\n')
cat('========================================\n')
"

echo "=========================================="
echo "Job completed: $COUNTRY iteration $ITER"
echo "End time: \$(date)"
echo "=========================================="
EOF

    # Submit job
    JOB_ID=$(sbatch --parsable $JOB_SCRIPT)
    JOB_IDS+=($JOB_ID)

    echo "  Job ID: $JOB_ID"

  done

  echo ""
  echo "Submitted ${#JOB_IDS[@]} jobs for iteration $ITER"
  echo "Job IDs: ${JOB_IDS[@]}"
  echo ""

  # Wait for all jobs in this iteration to complete
  echo "Waiting for iteration $ITER to complete..."

  for JOB_ID in "${JOB_IDS[@]}"; do
    # Poll job status until completed
    while true; do
      JOB_STATE=$(sacct -j $JOB_ID --format=State --noheader | head -1 | tr -d ' ')

      if [[ "$JOB_STATE" == "COMPLETED" ]]; then
        echo "  Job $JOB_ID: COMPLETED"
        break
      elif [[ "$JOB_STATE" == "FAILED" ]] || [[ "$JOB_STATE" == "CANCELLED" ]]; then
        echo "  Job $JOB_ID: $JOB_STATE"
        echo "ERROR: Job failed. Check logs in $LOG_DIR"
        exit 1
      else
        # Still running
        sleep 30
      fi
    done
  done

  echo ""
  echo "Iteration $ITER complete!"
  echo ""

  # Check convergence (if iter > 0)
  if [ $ITER -gt 0 ]; then
    echo "Checking convergence..."

    # Simple convergence check: compare trajectories to previous iteration
    # (In production, compute R² or other metric)

    ALL_CONVERGED=true
    for COUNTRY in "${COUNTRIES[@]}"; do
      CURR_TRAJ="${SHARED_DIR}/trajectories/${COUNTRY}_iter_$(printf '%03d' $ITER)_trajectory.csv"
      PREV_TRAJ="${SHARED_DIR}/trajectories/${COUNTRY}_iter_$(printf '%03d' $((ITER-1)))_trajectory.csv"

      if [ ! -f "$CURR_TRAJ" ] || [ ! -f "$PREV_TRAJ" ]; then
        echo "  WARNING: Missing trajectory for $COUNTRY"
        ALL_CONVERGED=false
        continue
      fi

      # Placeholder convergence check (just check file sizes are similar)
      CURR_SIZE=$(wc -l < "$CURR_TRAJ")
      PREV_SIZE=$(wc -l < "$PREV_TRAJ")

      echo "  $COUNTRY: current=$CURR_SIZE lines, previous=$PREV_SIZE lines"
    done

    # In production, compute actual R² here
    echo "  Note: Implement R² convergence check for production use"
    echo ""
  fi

done

# ==============================================================================
# Final Summary
# ==============================================================================

echo "========================================"
echo "Coupled Calibration Complete!"
echo "========================================"
echo "Iterations completed: $((N_ITERATIONS + 1))"
echo "Countries: ${COUNTRIES[@]}"
echo ""
echo "Results location:"
echo "  Outputs: ${SHARED_DIR}/output/"
echo "  Trajectories: ${SHARED_DIR}/trajectories/"
echo "  Logs: ${SHARED_DIR}/logs/"
echo ""
echo "Next steps:"
echo "  1. Check convergence: Rscript -e 'source(\"vm/analyze_coupling_convergence.R\")'"
echo "  2. Compare to single-node coupled model for validation"
echo "  3. Visualize trajectories: Rscript -e 'source(\"vm/plot_coupled_trajectories.R\")'"
echo "========================================"
