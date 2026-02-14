#!/bin/bash
# ==============================================================================
# SLURM Job Array Submission - Parallel MOSAIC Country Runs
# ==============================================================================
# Usage: sbatch submit_parallel_countries_slurm.sh
# ==============================================================================

#SBATCH --job-name=mosaic_multi
#SBATCH --output=logs/mosaic_%A_%a.out
#SBATCH --error=logs/mosaic_%A_%a.err
#SBATCH --array=0-7                    # 8 countries (0-indexed)
#SBATCH --nodes=1                      # One node per country
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32             # Adjust based on node capacity
#SBATCH --mem=64G                      # Adjust based on country size
#SBATCH --time=24:00:00                # Max runtime per country

# Create log directory
mkdir -p logs

# Define country list (must match array size)
COUNTRIES=(
  "MOZ"  # 0
  "MWI"  # 1
  "ZMB"  # 2
  "ZWE"  # 3
  "TZA"  # 4
  "KEN"  # 5
  "ETH"  # 6
  "SOM"  # 7
)

# Get country for this array task
ISO_CODE=${COUNTRIES[$SLURM_ARRAY_TASK_ID]}

echo "=========================================="
echo "SLURM Job Array - MOSAIC Calibration"
echo "=========================================="
echo "Job ID: $SLURM_JOB_ID"
echo "Array Task ID: $SLURM_ARRAY_TASK_ID"
echo "Country: $ISO_CODE"
echo "Node: $SLURMD_NODENAME"
echo "Cores: $SLURM_CPUS_PER_TASK"
echo "=========================================="

# Load modules (adjust for your cluster)
# module load R/4.3.0
# module load gcc/11.2.0
# module load conda

# Activate conda environment if needed
# source ~/miniconda3/etc/profile.d/conda.sh
# conda activate mosaic-conda-env

# Run MOSAIC for this country
Rscript vm/run_single_country.R $ISO_CODE

echo "=========================================="
echo "Job completed: $ISO_CODE"
echo "=========================================="
