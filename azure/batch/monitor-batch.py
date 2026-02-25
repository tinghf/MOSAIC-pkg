#!/usr/bin/env python3
"""
Azure Batch Job Monitor for MOSAIC
===================================

Monitor running batch jobs and download results.

Usage:
    python monitor-batch.py --job-id mosaic-20260224-120000
    python monitor-batch.py --list-jobs
"""

import argparse
import os
import time
from azure.batch import BatchServiceClient
from azure.batch.batch_auth import SharedKeyCredentials

BATCH_ACCOUNT_NAME = os.getenv("BATCH_ACCOUNT_NAME", "mosaicbatch")
BATCH_ACCOUNT_URL = f"https://{BATCH_ACCOUNT_NAME}.eastus.batch.azure.com"


def create_batch_client():
    """Create Azure Batch client."""
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


def list_jobs():
    """List all batch jobs."""
    batch_client = create_batch_client()

    print("Active Batch Jobs:")
    print("-" * 80)
    print(f"{'Job ID':<30} {'State':<15} {'Tasks':<20}")
    print("-" * 80)

    for job in batch_client.job.list():
        task_counts = batch_client.job.get_task_counts(job.id)
        tasks_str = (
            f"{task_counts.completed}/{task_counts.active + task_counts.completed}"
        )

        print(f"{job.id:<30} {job.state.value:<15} {tasks_str:<20}")


def monitor_job(job_id, follow=False, interval=30):
    """Monitor a specific job."""
    batch_client = create_batch_client()

    while True:
        try:
            job = batch_client.job.get(job_id)
            task_counts = batch_client.job.get_task_counts(job_id)

            print(f"\n{'=' * 80}")
            print(f"Job: {job_id}")
            print(f"State: {job.state.value}")
            print(f"{'=' * 80}")

            # Task summary
            total_tasks = (
                task_counts.active + task_counts.running + task_counts.completed
            )
            print(f"\nTask Summary:")
            print(f"  Active:    {task_counts.active}")
            print(f"  Running:   {task_counts.running}")
            print(f"  Completed: {task_counts.completed}/{total_tasks}")
            if task_counts.failed > 0:
                print(f"  Failed:    {task_counts.failed}")

            # List task details
            print(f"\nTask Details:")
            print(
                f"{'Task ID':<25} {'State':<15} {'Start Time':<20} {'End Time':<20}"
            )
            print("-" * 80)

            for task in batch_client.task.list(job_id):
                start_time = (
                    task.execution_info.start_time.strftime("%Y-%m-%d %H:%M:%S")
                    if task.execution_info and task.execution_info.start_time
                    else "N/A"
                )
                end_time = (
                    task.execution_info.end_time.strftime("%Y-%m-%d %H:%M:%S")
                    if task.execution_info and task.execution_info.end_time
                    else "N/A"
                )

                print(
                    f"{task.id:<25} {task.state.value:<15} {start_time:<20} {end_time:<20}"
                )

                # Show exit code if completed
                if task.execution_info and task.execution_info.exit_code is not None:
                    exit_code = task.execution_info.exit_code
                    status = "✓" if exit_code == 0 else "✗"
                    print(f"    Exit code: {exit_code} {status}")

            # Check if job is complete
            if job.state.value == "completed":
                print("\n✓ Job completed!")
                break

            if not follow:
                break

            print(f"\nRefreshing in {interval} seconds... (Ctrl+C to stop)")
            time.sleep(interval)

        except KeyboardInterrupt:
            print("\nMonitoring stopped.")
            break


def download_task_logs(job_id, task_id, output_dir="./logs"):
    """Download logs for a specific task."""
    import subprocess

    os.makedirs(output_dir, exist_ok=True)

    print(f"Downloading logs for {task_id}...")

    # Download stdout
    stdout_path = os.path.join(output_dir, f"{task_id}_stdout.txt")
    subprocess.run(
        [
            "az",
            "batch",
            "task",
            "file",
            "download",
            "--job-id",
            job_id,
            "--task-id",
            task_id,
            "--file-path",
            "stdout.txt",
            "--destination",
            stdout_path,
        ]
    )

    # Download stderr
    stderr_path = os.path.join(output_dir, f"{task_id}_stderr.txt")
    subprocess.run(
        [
            "az",
            "batch",
            "task",
            "file",
            "download",
            "--job-id",
            job_id,
            "--task-id",
            task_id,
            "--file-path",
            "stderr.txt",
            "--destination",
            stderr_path,
        ]
    )

    print(f"Logs downloaded to: {output_dir}/")


def main():
    parser = argparse.ArgumentParser(description="Monitor Azure Batch jobs")
    parser.add_argument("--job-id", help="Job ID to monitor")
    parser.add_argument(
        "--list-jobs", action="store_true", help="List all active jobs"
    )
    parser.add_argument(
        "--follow",
        "-f",
        action="store_true",
        help="Continuously monitor job",
    )
    parser.add_argument(
        "--interval", type=int, default=30, help="Refresh interval (seconds)"
    )
    parser.add_argument(
        "--download-logs",
        help="Download logs for specific task (format: job-id:task-id)",
    )

    args = parser.parse_args()

    if args.list_jobs:
        list_jobs()
    elif args.download_logs:
        job_id, task_id = args.download_logs.split(":")
        download_task_logs(job_id, task_id)
    elif args.job_id:
        monitor_job(args.job_id, follow=args.follow, interval=args.interval)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
