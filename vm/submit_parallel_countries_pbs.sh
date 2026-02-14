#!/bin/bash
# ==============================================================================
# PBS/Torque Job Array Submission - Parallel MOSAIC Country Runs
# ==============================================================================
# Usage: qsub submit_parallel_countries_pbs.sh
# ==============================================================================

#PBS -N mosaic_multi
#PBS -o logs/mosaic_${PBS_JOBID}.out
#PBS -e logs/mosaic_${PBS_JOBID}.err
#PBS -t 0-7                           # 8 countries (0-indexed)
#PBS -l nodes=1:ppn=32                # One node per country, 32 cores
#PBS -l mem=64gb                      # Adjust based on country size
#PBS -l walltime=24:00:00             # Max runtime per country

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
ISO_CODE=${COUNTRIES[$PBS_ARRAYID]}

# Change to working directory
cd $PBS_O_WORKDIR

echo "=========================================="
echo "PBS Job Array - MOSAIC Calibration"
echo "=========================================="
echo "Job ID: $PBS_JOBID"
echo "Array Task ID: $PBS_ARRAYID"
echo "Country: $ISO_CODE"
echo "Node: $(hostname)"
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
