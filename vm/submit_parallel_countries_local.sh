#!/bin/bash
# ==============================================================================
# Local Parallel Submission - For Multiple VMs/Machines Without Scheduler
# ==============================================================================
# Usage: bash submit_parallel_countries_local.sh
#
# This script submits independent country runs in the background.
# Use when you have multiple VMs/machines but no job scheduler.
# ==============================================================================

# Create log directory
mkdir -p logs

# Define countries
COUNTRIES=("MOZ" "MWI" "ZMB" "ZWE" "TZA" "KEN" "ETH" "SOM")

echo "=========================================="
echo "Launching ${#COUNTRIES[@]} parallel MOSAIC runs"
echo "=========================================="

# Launch each country in background
for ISO_CODE in "${COUNTRIES[@]}"; do
  echo "Starting: $ISO_CODE"
  nohup Rscript vm/run_single_country.R $ISO_CODE \
    > logs/mosaic_${ISO_CODE}.out \
    2> logs/mosaic_${ISO_CODE}.err &

  # Store process ID
  echo $! > logs/mosaic_${ISO_CODE}.pid

  sleep 2  # Brief delay between launches
done

echo "=========================================="
echo "All jobs submitted!"
echo ""
echo "Monitor progress:"
echo "  tail -f logs/mosaic_*.out"
echo ""
echo "Check running jobs:"
echo "  ps aux | grep run_single_country.R"
echo ""
echo "Kill a specific country:"
echo "  kill \$(cat logs/mosaic_ETH.pid)"
echo "=========================================="
