#!/usr/bin/env python
"""
Test MOSAIC worker script locally in Docker
Runs the same code that would run on Coiled workers

Usage:
    python azure/test_mosaic_worker_local.py --iso ETH
"""

import sys
import argparse
import subprocess
import tempfile
from pathlib import Path


def run_mosaic_test(iso_code, n_simulations=10, n_iterations=1):
    """
    Test MOSAIC calibration in Docker container locally
    """

    # Create R script
    r_script = f"""
library(MOSAIC)

# Set root directory
set_root_directory('/workspace')

# Configure MOSAIC for this country
iso_codes <- c("{iso_code}")

cat(strrep("=", 70), "\\n")
cat("MOSAIC Test Calibration: {iso_code}\\n")
cat(strrep("=", 70), "\\n")
cat("Step 1: Getting location config...\\n")
config <- get_location_config(iso=iso_codes)
cat("  ✓ Config loaded for:", config$location_name, "\\n")

cat("Step 2: Getting location priors...\\n")
priors <- get_location_priors(iso=iso_codes)
cat("  ✓ Priors loaded\\n")

cat("Step 3: Setting up control parameters...\\n")
control <- mosaic_control_defaults()
control$calibration$n_simulations <- {n_simulations}
control$calibration$n_iterations <- {n_iterations}
control$parallel$enable <- TRUE
control$parallel$n_cores <- max(1, parallel::detectCores() - 1)
cat("  ✓ Simulations:", {n_simulations}, "\\n")
cat("  ✓ Iterations:", {n_iterations}, "\\n")
cat("  ✓ Cores:", control$parallel$n_cores, "\\n")

cat("Step 4: Creating output directory...\\n")
dir_output <- file.path('/workspace', 'output', '{iso_code}')
dir.create(dir_output, recursive = TRUE, showWarnings = FALSE)
cat("  ✓ Output dir:", dir_output, "\\n")

cat(strrep("=", 70), "\\n")
cat("Starting MOSAIC calibration...\\n")
cat(strrep("=", 70), "\\n")

# Run MOSAIC (existing proven workflow!)
tryCatch({{
    result <- run_MOSAIC(
        dir_output = dir_output,
        config = config,
        priors = priors,
        control = control
    )
    cat("\\n")
    cat(strrep("=", 70), "\\n")
    cat("✅ MOSAIC calibration complete for {iso_code}!\\n")
    cat(strrep("=", 70), "\\n")
}}, error = function(e) {{
    cat("\\n")
    cat(strrep("=", 70), "\\n")
    cat("❌ ERROR in MOSAIC calibration:\\n")
    cat(strrep("=", 70), "\\n")
    cat("Error message:\\n")
    cat(as.character(e$message), "\\n")
    cat("\\n")
    cat("Traceback:\\n")
    print(sys.calls())
    quit(status = 1)
}})
"""

    print("="*70)
    print(f"Local Docker Test: MOSAIC Calibration for {iso_code}")
    print("="*70)
    print(f"Simulations: {n_simulations}")
    print(f"Iterations: {n_iterations}")
    print("="*70)
    print()

    # Write R script to temp file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.R', delete=False) as f:
        f.write(r_script)
        script_path = f.name

    print(f"Running R script in Docker container...")
    print(f"Container: ttingidmod/mosaic-worker:latest")
    print()

    try:
        # Run in Docker container
        result = subprocess.run(
            [
                'docker', 'run', '--rm',
                '-v', f'{script_path}:/tmp/test_script.R',
                'ttingidmod/mosaic-worker:latest',
                'Rscript', '/tmp/test_script.R'
            ],
            capture_output=False,  # Show output in real-time
            text=True,
            timeout=3600  # 1 hour timeout
        )

        print()
        print("="*70)
        if result.returncode == 0:
            print(f"✅ Test PASSED: MOSAIC ran successfully for {iso_code}")
            print("="*70)
            return 0
        else:
            print(f"❌ Test FAILED: Exit code {result.returncode}")
            print("="*70)
            return 1

    except subprocess.TimeoutExpired:
        print()
        print("="*70)
        print("❌ Test TIMEOUT: Exceeded 1 hour")
        print("="*70)
        return 1
    finally:
        # Cleanup temp file
        try:
            Path(script_path).unlink()
        except:
            pass


def main():
    parser = argparse.ArgumentParser(
        description='Test MOSAIC worker script locally in Docker'
    )
    parser.add_argument(
        '--iso',
        default='ETH',
        help='ISO code to test (default: ETH)'
    )
    parser.add_argument(
        '--n-simulations',
        type=int,
        default=10,
        help='Number of simulations (default: 10 for quick test)'
    )
    parser.add_argument(
        '--n-iterations',
        type=int,
        default=1,
        help='Number of iterations (default: 1 for quick test)'
    )

    args = parser.parse_args()

    return run_mosaic_test(
        args.iso,
        args.n_simulations,
        args.n_iterations
    )


if __name__ == "__main__":
    sys.exit(main())
