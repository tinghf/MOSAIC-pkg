"""
MOSAIC Coiled Runner
Parallelizes LASER simulations across a Dask cluster using Coiled.

Usage:
    python run_mosaic_coiled.py --iso ETH --n-simulations 1000 --n-iterations 3 --n-workers 10

Author: MOSAIC Team
Last Updated: 2026-02-24
"""

import os
import json
import time
import warnings
from pathlib import Path
from typing import Dict, List, Any

import coiled
import dask
from dask.distributed import Client, as_completed
import numpy as np
import pandas as pd

# Suppress warnings
warnings.filterwarnings('ignore')

# =============================================================================
# Configuration
# =============================================================================

# Worker configuration
WORKER_VM_TYPE = "Standard_D4s_v6"  # Azure: 4 cores, 16GB RAM
WORKER_REGION = "westus2"  # Azure region
KEEPALIVE_MINUTES = 120  # 2 hours - workers persist to avoid reinstalling MOSAIC

# Software environment (must be pre-created via coiled CLI)
SOFTWARE_ENV = "mosaic-pkg"

# =============================================================================
# R Interface via subprocess (avoids rpy2 serialization issues)
# =============================================================================

def setup_r_environment():
    """
    Initialize R environment check script.
    Returns script that can be executed on workers.
    """
    return """
    library(MOSAIC)
    MOSAIC::attach_mosaic_env(silent=TRUE)
    cat("R environment ready\\n")
    """

def create_r_runner_script(iso_codes: List[str]) -> str:
    """
    Create R script that loads config/priors and runs LASER simulation.

    Parameters
    ----------
    iso_codes : list of str
        Country ISO codes

    Returns
    -------
    str
        R script content
    """
    iso_vec = '", "'.join(iso_codes)
    return f"""
    library(MOSAIC)
    MOSAIC::attach_mosaic_env(silent=TRUE)

    # Set root directory (required for get_paths)
    set_root_directory('~/MOSAIC')

    # Load configuration
    iso_codes <- c("{iso_vec}")
    config <- get_location_config(iso=iso_codes)
    priors <- get_location_priors(iso=iso_codes)

    # Read parameter JSON from stdin
    param_json <- readLines("stdin")
    params <- jsonlite::fromJSON(param_json)

    # Run LASER
    result <- run_LASER(
        params = params,
        config = config,
        priors = priors,
        return_format = 'list'
    )

    # Convert to JSON and write to stdout
    cat(jsonlite::toJSON(result, auto_unbox=TRUE))
    """

def run_laser_via_subprocess(
    param_dict: Dict[str, float],
    r_script: str
) -> Dict[str, Any]:
    """
    Run LASER simulation by executing R script in subprocess.
    This avoids rpy2 serialization issues with large objects.

    Parameters
    ----------
    param_dict : dict
        Parameter dictionary
    r_script : str
        R script content

    Returns
    -------
    dict
        Simulation results
    """
    import subprocess
    import tempfile

    # Write R script to temp file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.R', delete=False) as f:
        f.write(r_script)
        script_path = f.name

    try:
        # Run R script with parameter JSON via stdin
        param_json = json.dumps(param_dict)

        # Set RETICULATE_PYTHON to use Coiled's Python (critical for LASER simulations!)
        env = os.environ.copy()
        env['RETICULATE_PYTHON'] = '/opt/coiled/env/bin/python'

        process = subprocess.run(
            ['Rscript', script_path],
            input=param_json,
            capture_output=True,
            text=True,
            timeout=300,  # 5 minute timeout per simulation
            env=env  # Pass environment with RETICULATE_PYTHON set
        )

        if process.returncode != 0:
            raise RuntimeError(f"R script failed: {process.stderr}")

        # Parse JSON output
        result = json.loads(process.stdout)
        result['params'] = param_dict
        return result

    finally:
        # Clean up temp file
        os.unlink(script_path)

# =============================================================================
# Coiled Functions
# =============================================================================

def _ensure_mosaic_installed():
    """
    Ensure MOSAIC R package is installed on worker.
    This is cached across tasks, so only runs once per worker.
    """
    import subprocess
    import os

    # Check if already installed (try actually loading, not just checking namespace)
    check_script = """
    tryCatch({
        library(MOSAIC)
        cat('installed')
    }, error = function(e) {
        cat('missing')
    })
    """

    result = subprocess.run(
        ['Rscript', '-e', check_script],
        capture_output=True,
        text=True,
        timeout=10
    )

    if 'installed' in result.stdout:
        print("MOSAIC already installed on worker")
        return  # Already installed

    # Install MOSAIC
    print("Installing MOSAIC R package on worker (one-time, ~5 minutes)...")

    # Create .condarc for r-miniconda BEFORE running R script
    import pathlib
    conda_dir = pathlib.Path.home() / '.local' / 'share' / 'r-miniconda'
    conda_dir.mkdir(parents=True, exist_ok=True)
    conda_rc = conda_dir / '.condarc'

    # Write condarc with conda-forge only + accept ToS
    with open(conda_rc, 'w') as f:
        f.write('channels:\n')
        f.write('  - conda-forge\n')
        f.write('channel_priority: strict\n')
        f.write('tos_accepted:\n')
        f.write('  - https://repo.anaconda.com/pkgs/main\n')
        f.write('  - https://repo.anaconda.com/pkgs/r\n')

    print(f"Created {conda_rc} for conda-forge only with ToS accepted")

    install_script = """
    options(repos = c(CRAN = 'https://cloud.r-project.org'))

    # Create user library
    dir.create('~/R/library', recursive=TRUE, showWarnings=FALSE)
    .libPaths(c('~/R/library', .libPaths()))

    # Accept Anaconda ToS via conda command
    system('~/.local/share/r-miniconda/bin/conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true')
    system('~/.local/share/r-miniconda/bin/conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true')

    # Install MOSAIC R package (explicit repo reference)
    cat('Installing MOSAIC from GitHub...\\n')
    remotes::install_github(
        repo = 'InstituteforDiseaseModeling/MOSAIC-pkg',
        ref = 'main',
        dependencies = TRUE,
        upgrade = 'never',
        force = TRUE
    )

    # Verify it installed MOSAIC (not a dependency)
    if (!requireNamespace('MOSAIC', quietly=FALSE)) {
        stop('MOSAIC package not found after installation!')
    }
    cat('MOSAIC package verified\\n')

    # Use Coiled's existing Python instead of installing Miniconda
    # This avoids Anaconda ToS errors from nested conda install
    Sys.setenv(RETICULATE_PYTHON = '/opt/coiled/env/bin/python')

    library(MOSAIC)

    # Skip install_dependencies - Coiled env already has Python
    # Just attach/verify the environment
    cat('Using Coiled Python environment\\n')
    cat('Python:', Sys.getenv('RETICULATE_PYTHON'), '\\n')

    # Verify MOSAIC loaded
    cat('MOSAIC loaded successfully\\n')
    """

    # Set environment variables
    env = os.environ.copy()
    env['CONDARC'] = str(conda_rc)
    env['RETICULATE_PYTHON'] = '/opt/coiled/env/bin/python'  # Tell reticulate to use Coiled's Python

    result = subprocess.run(
        ['Rscript', '-e', install_script],
        capture_output=True,
        text=True,
        timeout=1800,  # 30 minute timeout for installation (GitHub download + deps)
        env=env  # Pass environment with CONDARC set
    )

    if result.returncode != 0:
        print(f"❌ MOSAIC installation failed!")
        print(f"Stdout: {result.stdout[:1000]}")
        print(f"Stderr: {result.stderr[:1000]}")
        raise RuntimeError(f"MOSAIC installation failed with exit code {result.returncode}")

    print("✅ MOSAIC installed successfully on worker")
    print(f"Installation output: {result.stdout[:500]}")

def run_laser_remote(param_dict: Dict[str, float], r_script: str) -> Dict[str, Any]:
    """
    Remote function executed on Coiled workers.
    Runs single LASER simulation.

    Parameters
    ----------
    param_dict : dict
        Parameter values (e.g., {'beta': 0.5, 'gamma': 0.1, ...})
    r_script : str
        R script content for running LASER

    Returns
    -------
    dict
        Simulation results with keys: 'cases', 'deaths', 'time', 'params'
    """
    # Ensure MOSAIC is installed (cached, only runs once per worker)
    _ensure_mosaic_installed()

    return run_laser_via_subprocess(param_dict, r_script)

# =============================================================================
# Likelihood Computation (Local)
# =============================================================================

def compute_likelihoods_batch(
    results: List[Dict[str, Any]],
    observed_data: Dict[str, Any],
    control: Dict[str, Any]
) -> np.ndarray:
    """
    Compute likelihoods for batch of simulation results.
    This is done locally (not on cluster) since it's fast.

    Parameters
    ----------
    results : list of dict
        Simulation results from workers
    observed_data : dict
        Observed cases/deaths from config
    control : dict
        Control parameters for likelihood calculation

    Returns
    -------
    np.ndarray
        Likelihood values
    """
    import subprocess
    import tempfile

    # Write observed data and results to temp files
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump({
            'results': results,
            'observed': observed_data,
            'control': control
        }, f)
        data_file = f.name

    # R script to compute likelihoods
    r_script = f"""
    library(MOSAIC)
    data <- jsonlite::read_json("{data_file}")

    likelihoods <- sapply(data$results, function(result) {{
        MOSAIC::calc_model_likelihood(
            simulated_cases = result$cases,
            simulated_deaths = result$deaths,
            observed_cases = data$observed$cases,
            observed_deaths = data$observed$deaths,
            control = data$control
        )
    }})

    cat(jsonlite::toJSON(likelihoods))
    """

    with tempfile.NamedTemporaryFile(mode='w', suffix='.R', delete=False) as f:
        f.write(r_script)
        script_path = f.name

    try:
        process = subprocess.run(
            ['Rscript', script_path],
            capture_output=True,
            text=True,
            timeout=60
        )

        if process.returncode != 0:
            raise RuntimeError(f"Likelihood computation failed: {process.stderr}")

        likelihoods = json.loads(process.stdout)
        return np.array(likelihoods)

    finally:
        os.unlink(script_path)
        os.unlink(data_file)

# =============================================================================
# BFRS Workflow
# =============================================================================

def sample_parameters_r(
    iso_codes: List[str],
    n: int,
    weights: np.ndarray = None
) -> pd.DataFrame:
    """
    Sample parameters from priors using R.

    Parameters
    ----------
    iso_codes : list of str
        Country ISO codes (config/priors reloaded fresh for proper R structure)
    n : int
        Number of samples
    weights : np.ndarray, optional
        Importance weights for resampling

    Returns
    -------
    pd.DataFrame
        Parameter samples
    """
    import subprocess
    import tempfile

    # Write weights to temp file
    data = {'n': n}
    if weights is not None:
        data['weights'] = weights.tolist()

    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(data, f)
        data_file = f.name

    # Generate random seed for reproducibility
    seed = np.random.randint(1, 1000000)
    iso_vec = '", "'.join(iso_codes)

    r_script = f"""
    library(MOSAIC)
    set_root_directory('~/MOSAIC')

    # Reload config/priors fresh (maintains R structure)
    iso_codes <- c("{iso_vec}")
    config <- get_location_config(iso=iso_codes)
    priors <- get_location_priors(iso=iso_codes)

    # Load sampling parameters
    data <- jsonlite::read_json("{data_file}")
    weights <- if (is.null(data$weights)) NULL else unlist(data$weights)

    params <- MOSAIC::sample_parameters(
        config = config,
        priors = priors,
        n = data$n,
        weights = weights,
        seed = {seed},
        verbose = FALSE
    )

    # Convert to JSON
    cat(jsonlite::toJSON(params))
    """

    with tempfile.NamedTemporaryFile(mode='w', suffix='.R', delete=False) as f:
        f.write(r_script)
        script_path = f.name

    try:
        process = subprocess.run(
            ['Rscript', script_path],
            capture_output=True,
            text=True,
            timeout=60
        )

        if process.returncode != 0:
            raise RuntimeError(f"Parameter sampling failed: {process.stderr}")

        # Check if stdout is empty before parsing JSON
        if not process.stdout.strip():
            raise RuntimeError(f"Parameter sampling produced no output. Stderr: {process.stderr}")

        try:
            params_dict = json.loads(process.stdout)
        except json.JSONDecodeError as e:
            raise RuntimeError(f"Invalid JSON from parameter sampling. Stdout: {process.stdout[:500]}, Stderr: {process.stderr}")

        return pd.DataFrame(params_dict)

    finally:
        os.unlink(script_path)
        os.unlink(data_file)

def update_weights_gibbs(
    likelihoods: np.ndarray,
    prev_weights: np.ndarray
) -> np.ndarray:
    """
    Update weights using Gibbs sampling (via R).

    Parameters
    ----------
    likelihoods : np.ndarray
        Likelihood values
    prev_weights : np.ndarray
        Previous weights

    Returns
    -------
    np.ndarray
        Updated weights
    """
    import subprocess
    import tempfile

    data = {
        'likelihoods': likelihoods.tolist(),
        'weights': prev_weights.tolist()
    }

    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(data, f)
        data_file = f.name

    r_script = f"""
    library(MOSAIC)
    data <- jsonlite::read_json("{data_file}")

    new_weights <- MOSAIC::calc_model_weights_gibbs(
        likelihoods = unlist(data$likelihoods),
        prev_weights = unlist(data$weights)
    )

    cat(jsonlite::toJSON(new_weights))
    """

    with tempfile.NamedTemporaryFile(mode='w', suffix='.R', delete=False) as f:
        f.write(r_script)
        script_path = f.name

    try:
        process = subprocess.run(
            ['Rscript', script_path],
            capture_output=True,
            text=True,
            timeout=30
        )

        if process.returncode != 0:
            raise RuntimeError(f"Weight update failed: {process.stderr}")

        weights = json.loads(process.stdout)
        return np.array(weights)

    finally:
        os.unlink(script_path)
        os.unlink(data_file)

def run_mosaic_bfrs_coiled(
    iso_codes: List[str],
    n_simulations: int = 1000,
    n_iterations: int = 3,
    n_workers: int = 10,
    output_dir: str = "./output",
    control: Dict[str, Any] = None
) -> Dict[str, Any]:
    """
    Run MOSAIC BFRS calibration using Coiled.

    Parameters
    ----------
    iso_codes : list of str
        Country ISO codes (e.g., ['ETH', 'KEN'])
    n_simulations : int
        Number of simulations per iteration
    n_iterations : int
        Number of BFRS iterations
    n_workers : int
        Number of Dask workers to spawn
    output_dir : str
        Output directory for results
    control : dict, optional
        Control parameters (defaults loaded from MOSAIC)

    Returns
    -------
    dict
        Results summary
    """

    print("="*70)
    print("MOSAIC Coiled Calibration")
    print("="*70)
    print(f"ISO codes: {', '.join(iso_codes)}")
    print(f"Simulations: {n_simulations}")
    print(f"Iterations: {n_iterations}")
    print(f"Workers: {n_workers}")
    print(f"Output: {output_dir}")
    print("="*70)
    print()

    # Create output directory
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    # Load configuration and priors (locally, via R)
    print("📦 Loading configuration and priors...")

    # Load actual MOSAIC config and priors via R subprocess
    import subprocess
    import tempfile

    iso_vec = '", "'.join(iso_codes)
    load_script = f"""
    library(MOSAIC)
    MOSAIC::attach_mosaic_env(silent=TRUE)

    # Set root directory (required for get_location_config)
    set_root_directory('~/MOSAIC')

    iso_codes <- c("{iso_vec}")
    config <- get_location_config(iso=iso_codes)
    priors <- get_location_priors(iso=iso_codes)

    # Convert to JSON for Python
    result <- list(
        config = config,
        priors = priors
    )
    cat(jsonlite::toJSON(result, auto_unbox=TRUE))
    """

    with tempfile.NamedTemporaryFile(mode='w', suffix='.R', delete=False) as f:
        f.write(load_script)
        load_script_path = f.name

    try:
        process = subprocess.run(
            ['Rscript', load_script_path],
            capture_output=True,
            text=True,
            timeout=300  # 5 minute timeout
        )

        if process.returncode != 0:
            raise RuntimeError(f"Failed to load config/priors: {process.stderr}")

        data = json.loads(process.stdout)
        config = data['config']
        priors = data['priors']
        observed_data = {
            'cases': config.get('observed_cases', []),
            'deaths': config.get('observed_deaths', [])
        }

        print(f"   ✅ Loaded config for {len(iso_codes)} countries")
        print(f"   ✅ Loaded priors for {len(priors)} parameters")

    finally:
        os.unlink(load_script_path)

    # Create R script for workers
    r_script = create_r_runner_script(iso_codes)

    # Create Coiled cluster
    print(f"☁️  Spinning up Coiled cluster with {n_workers} workers...")
    cluster_name = f"mosaic-{'-'.join(iso_codes)}-{int(time.time())}"

    cluster = coiled.Cluster(
        name=cluster_name,
        n_workers=n_workers,
        worker_vm_types=[WORKER_VM_TYPE],
        region=WORKER_REGION,
        software=SOFTWARE_ENV,
        shutdown_on_close=True,
        idle_timeout=f"{KEEPALIVE_MINUTES} minutes",  # Keep cluster alive when idle
        scheduler_options={"idle_timeout": f"{KEEPALIVE_MINUTES*60}s"},  # Use underscores not hyphens
        worker_options={"death_timeout": "3600s"}  # Use underscores not hyphens
    )

    client = Client(cluster)
    print(f"✅ Cluster ready: {client.dashboard_link}")
    print()

    # BFRS iterations
    weights = np.ones(n_simulations) / n_simulations
    all_params = []
    all_likelihoods = []

    for iteration in range(n_iterations):
        print(f"{'='*70}")
        print(f"Iteration {iteration + 1}/{n_iterations}")
        print(f"{'='*70}")

        # Sample parameters
        print(f"📦 Sampling {n_simulations} parameter sets...")
        params_df = sample_parameters_r(iso_codes, n_simulations, weights)
        param_dicts = params_df.to_dict('records')

        # Add unique ID to each parameter set
        for i, p in enumerate(param_dicts):
            p['_id'] = f"iter{iteration}_sim{i}"

        # Submit LASER simulations to Coiled
        print(f"🚀 Submitting {n_simulations} simulations to cluster...")
        start_time = time.time()

        # Create delayed tasks
        delayed_tasks = [
            dask.delayed(run_laser_remote)(p, r_script)
            for p in param_dicts
        ]

        # Submit to cluster and get futures
        futures = client.compute(delayed_tasks)

        # Track progress
        results = []
        completed = 0
        for future, result in as_completed(futures, with_results=True):
            results.append(result)
            completed += 1
            if completed % 100 == 0:
                elapsed = time.time() - start_time
                rate = completed / elapsed
                remaining = (n_simulations - completed) / rate
                print(f"  Progress: {completed}/{n_simulations} ({completed/n_simulations*100:.1f}%) "
                      f"- ETA: {remaining/60:.1f} min")

        elapsed = time.time() - start_time
        print(f"✅ All simulations complete in {elapsed/60:.1f} minutes")

        # Compute likelihoods
        print(f"📊 Computing likelihoods...")
        likelihoods = compute_likelihoods_batch(results, observed_data, control or {})

        # Update weights
        print(f"⚖️  Updating weights...")
        weights = update_weights_gibbs(likelihoods, weights)

        # Convergence metrics
        ess = 1 / np.sum(weights**2)
        print(f"📈 Effective Sample Size: {ess:.1f}/{n_simulations}")

        # Store results
        params_df['likelihood'] = likelihoods
        params_df['weight'] = weights
        params_df['iteration'] = iteration
        all_params.append(params_df)
        all_likelihoods.append(likelihoods)

        # Save checkpoint
        checkpoint = {
            'iteration': iteration,
            'ess': float(ess),
            'mean_likelihood': float(np.mean(likelihoods)),
            'max_likelihood': float(np.max(likelihoods)),
            'elapsed_minutes': elapsed / 60
        }
        checkpoint_file = output_path / f'checkpoint_iter_{iteration}.json'
        with open(checkpoint_file, 'w') as f:
            json.dump(checkpoint, f, indent=2)
        print(f"💾 Checkpoint saved: {checkpoint_file}")
        print()

    # Final results
    print(f"{'='*70}")
    print(f"🎉 BFRS Calibration Complete")
    print(f"{'='*70}")

    # Combine all iterations
    all_params_df = pd.concat(all_params, ignore_index=True)

    # Save final results
    output_file = output_path / 'simulations.parquet'
    all_params_df.to_parquet(output_file)
    print(f"💾 Results saved: {output_file}")

    # Summary statistics
    summary = {
        'n_iterations': n_iterations,
        'n_simulations': n_simulations,
        'total_simulations': len(all_params_df),
        'final_ess': float(ess),
        'dashboard_link': client.dashboard_link,
        'output_dir': str(output_path)
    }

    summary_file = output_path / 'summary.json'
    with open(summary_file, 'w') as f:
        json.dump(summary, f, indent=2)

    # Cleanup cluster
    print(f"☁️  Shutting down cluster...")
    client.close()
    cluster.close()

    print(f"✅ Done!")
    print()

    return summary

# =============================================================================
# CLI
# =============================================================================

def main():
    import argparse

    parser = argparse.ArgumentParser(
        description='Run MOSAIC BFRS calibration on Coiled',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument(
        '--iso',
        required=True,
        help='Comma-separated ISO country codes (e.g., ETH,KEN)'
    )
    parser.add_argument(
        '--n-simulations',
        type=int,
        default=1000,
        help='Number of simulations per iteration'
    )
    parser.add_argument(
        '--n-iterations',
        type=int,
        default=3,
        help='Number of BFRS iterations'
    )
    parser.add_argument(
        '--n-workers',
        type=int,
        default=10,
        help='Number of Dask workers'
    )
    parser.add_argument(
        '--output-dir',
        default='./output',
        help='Output directory'
    )

    args = parser.parse_args()

    iso_codes = [x.strip().upper() for x in args.iso.split(',')]

    try:
        result = run_mosaic_bfrs_coiled(
            iso_codes=iso_codes,
            n_simulations=args.n_simulations,
            n_iterations=args.n_iterations,
            n_workers=args.n_workers,
            output_dir=args.output_dir
        )

        print("="*70)
        print("📊 Summary")
        print("="*70)
        print(f"Total simulations: {result['total_simulations']}")
        print(f"Final ESS: {result['final_ess']:.1f}")
        print(f"Results: {result['output_dir']}")
        print(f"Dashboard: {result['dashboard_link']}")
        print("="*70)

    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1

    return 0

if __name__ == "__main__":
    exit(main())
