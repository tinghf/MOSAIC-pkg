#!/usr/bin/env python3
"""
Azure Batch Job Submission for MOSAIC
======================================

Submits multiple MOSAIC calibrations as parallel batch tasks.

Usage:
    python submit-mosaic-batch.py --countries ETH,SOM,KEN,TZA --pool-size 4

Prerequisites:
    pip install azure-batch azure-storage-blob
    az batch account login --name mosaicbatch --resource-group mosaic-batch-rg
"""

import argparse
import datetime
import os
from azure.batch import BatchServiceClient
from azure.batch import models as batchmodels
from azure.common.credentials import ServicePrincipalCredentials
from azure.storage.blob import BlobServiceClient

# Configuration
BATCH_ACCOUNT_NAME = os.getenv("BATCH_ACCOUNT_NAME", "mosaicbatch")
BATCH_ACCOUNT_URL = f"https://{BATCH_ACCOUNT_NAME}.eastus.batch.azure.com"
POOL_ID = "mosaic-hpc-pool"
CONTAINER_REGISTRY = "mosaicidm.azurecr.io"
CONTAINER_IMAGE = f"{CONTAINER_REGISTRY}/mosaic:latest"


def create_batch_client():
    """Create Azure Batch client using Azure CLI credentials."""
    # Use Azure CLI credentials
    from azure.cli.core import get_default_cli
    from azure.batch.batch_auth import SharedKeyCredentials

    # Get credentials from Azure CLI
    cli = get_default_cli()
    # This will use 'az batch account login' credentials

    # Alternative: use account key
    import subprocess
    result = subprocess.run(
        [
            "az",
            "batch",
            "account",
            "keys",
            "list",
            "--name",
            BATCH_ACCOUNT_NAME,
            "--resource-group",
            "mosaic-batch-rg",
            "--query",
            "primary",
            "-o",
            "tsv",
        ],
        capture_output=True,
        text=True,
    )
    account_key = result.stdout.strip()

    credentials = SharedKeyCredentials(BATCH_ACCOUNT_NAME, account_key)
    return BatchServiceClient(credentials, batch_url=BATCH_ACCOUNT_URL)


def submit_mosaic_job(countries, n_simulations=1000, n_iterations=3, pool_size=None):
    """Submit MOSAIC calibration job to Azure Batch.

    Args:
        countries: List of ISO country codes
        n_simulations: Number of simulations per batch
        n_iterations: Number of BFRS iterations
        pool_size: Number of pool nodes (None = auto-scale)
    """
    batch_client = create_batch_client()

    # Generate unique job ID
    job_id = f"mosaic-{datetime.datetime.now().strftime('%Y%m%d-%H%M%S')}"

    print(f"Submitting job: {job_id}")
    print(f"Countries: {', '.join(countries)}")
    print(f"Pool: {POOL_ID}")
    print(f"Container: {CONTAINER_IMAGE}")
    print("")

    # Create job
    job = batchmodels.JobAddParameter(
        id=job_id,
        pool_info=batchmodels.PoolInformation(pool_id=POOL_ID),
        on_all_tasks_complete=batchmodels.OnAllTasksComplete.terminate_job,
    )

    batch_client.job.add(job)
    print(f"✓ Job created: {job_id}")

    # Resize pool if requested
    if pool_size:
        print(f"Scaling pool to {pool_size} dedicated nodes...")
        batch_client.pool.resize(
            pool_id=POOL_ID,
            pool_resize_parameter=batchmodels.PoolResizeParameter(
                target_dedicated_nodes=pool_size, target_low_priority_nodes=0
            ),
        )

    # Add tasks (one per country)
    tasks = []
    for iso_code in countries:
        task_id = f"task-{iso_code}"

        # Container settings
        container_settings = batchmodels.TaskContainerSettings(
            image_name=CONTAINER_IMAGE,
            container_run_options="--rm --workdir /opt/MOSAIC-pkg",
        )

        # Environment variables
        env_settings = [
            batchmodels.EnvironmentSetting("ISO_CODE", iso_code),
            batchmodels.EnvironmentSetting("N_SIMULATIONS", str(n_simulations)),
            batchmodels.EnvironmentSetting("N_ITERATIONS", str(n_iterations)),
            batchmodels.EnvironmentSetting("N_CORES", "120"),
            batchmodels.EnvironmentSetting("TARGET_R2", "0.95"),
            batchmodels.EnvironmentSetting("OUTPUT_DIR", f"/outputs"),
        ]

        # Output files (upload results to blob storage)
        output_file = batchmodels.OutputFile(
            file_pattern="../stdout.txt",
            destination=batchmodels.OutputFileDestination(
                container=batchmodels.OutputFileBlobContainerDestination(
                    container_url=f"https://mosaicbatchstorage.blob.core.windows.net/outputs/{job_id}/{iso_code}/"
                )
            ),
            upload_options=batchmodels.OutputFileUploadOptions(
                upload_condition=batchmodels.OutputFileUploadCondition.task_completion
            ),
        )

        # Create task
        task = batchmodels.TaskAddParameter(
            id=task_id,
            command_line="/bin/bash -c '/usr/local/bin/entrypoint.sh'",
            container_settings=container_settings,
            environment_settings=env_settings,
            # output_files=[output_file],  # Uncomment if blob storage configured
        )

        tasks.append(task)
        print(f"  Adding task: {task_id} ({iso_code})")

    # Submit tasks
    batch_client.task.add_collection(job_id, tasks)
    print(f"\n✓ {len(tasks)} tasks submitted")

    # Print monitoring commands
    print("")
    print("Monitor job progress:")
    print(f"  az batch job show --job-id {job_id}")
    print(f"  az batch task list --job-id {job_id} --output table")
    print("")
    print("View task logs:")
    print(f"  az batch task file list --job-id {job_id} --task-id task-ETH")
    print(
        f"  az batch task file download --job-id {job_id} --task-id task-ETH --file-path stdout.txt"
    )
    print("")
    print("Download using Python script:")
    print(f"  python3 monitor-batch.py --job-id {job_id}")
    print("")

    return job_id


def main():
    parser = argparse.ArgumentParser(
        description="Submit MOSAIC calibration job to Azure Batch"
    )
    parser.add_argument(
        "--countries",
        required=True,
        help="Comma-separated ISO country codes (e.g., ETH,SOM,KEN)",
    )
    parser.add_argument(
        "--n-simulations", type=int, default=1000, help="Simulations per batch"
    )
    parser.add_argument(
        "--n-iterations", type=int, default=3, help="Number of BFRS iterations"
    )
    parser.add_argument(
        "--pool-size",
        type=int,
        help="Number of pool nodes (default: auto-scale)",
    )

    args = parser.parse_args()

    countries = [c.strip().upper() for c in args.countries.split(",")]

    job_id = submit_mosaic_job(
        countries=countries,
        n_simulations=args.n_simulations,
        n_iterations=args.n_iterations,
        pool_size=args.pool_size,
    )

    print(f"Job submitted: {job_id}")


if __name__ == "__main__":
    main()
