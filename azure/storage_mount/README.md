# Azure File Share Setup for MOSAIC Coiled Workers

This directory contains scripts to set up Azure File Share storage for MOSAIC data, enabling Coiled workers to access MOSAIC-data and MOSAIC-pkg repositories.

## Quick Start

```bash
cd ~/MOSAIC/MOSAIC-pkg/azure/storage_mount

# Step 1: Create file share (one-time setup)
./01_create_fileshare.sh

# Step 2: Populate with MOSAIC data (one-time, or when data updates)
./02_populate_fileshare.sh

# Step 3: Get mount credentials (for Coiled configuration)
./03_get_mount_credentials.sh
```

## What This Does

### File Share Structure
Creates this structure in Azure Files:
```
mosaic-shared-data/          # Azure File Share name
└── MOSAIC/                   # Root directory
    ├── MOSAIC-data/          # Data repository (150MB)
    │   ├── raw/
    │   └── processed/
    └── MOSAIC-pkg/           # Model configs
        └── model/
            ├── input/
            └── output/
```

### Storage Details
- **Account**: ttingeasyva
- **Location**: westus2 (same as Coiled workers)
- **Type**: Azure Files (SMB/CIFS)
- **Size**: 5GB quota (enough for 150MB data + growth)

## Usage with Coiled

After running the setup scripts, update your Coiled worker configuration:

### Option A: Mount in Dockerfile (Rebuild Required)

Update `azure/Dockerfile`:

```dockerfile
# Install cifs-utils for Azure Files mounting
RUN apt-get update && apt-get install -y cifs-utils && rm -rf /var/lib/apt/lists/*

# Create mount point
RUN mkdir -p /workspace/MOSAIC

# Add mount script
COPY azure/storage_mount/mount_fileshare.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/mount_fileshare.sh

# Mount on container start
CMD ["/bin/bash", "-c", "/usr/local/bin/mount_fileshare.sh && /bin/bash"]
```

### Option B: Mount at Runtime (No Rebuild Needed) ✅ RECOMMENDED

Update `azure/run_mosaic_parallel_country.py`:

```python
def run_mosaic_for_country(iso_code, output_dir, n_simulations=1000, n_iterations=3):
    """Run MOSAIC with Azure Files mount"""
    import subprocess
    import os

    # Get credentials from environment
    storage_account = os.environ.get('AZURE_STORAGE_ACCOUNT', 'ttingeasyva')
    storage_key = os.environ.get('AZURE_STORAGE_KEY')
    file_share = os.environ.get('AZURE_FILE_SHARE', 'mosaic-shared-data')

    # R script with mount commands
    r_script = f"""
    # Install cifs-utils if not present
    system('apt-get update && apt-get install -y cifs-utils 2>/dev/null || true')

    # Mount Azure File Share
    system('mkdir -p /workspace/MOSAIC')
    mount_cmd <- sprintf(
        'mount -t cifs //%s.file.core.windows.net/%s /workspace/MOSAIC -o vers=3.0,username=%s,password=%s,dir_mode=0777,file_mode=0777,serverino',
        '{storage_account}',
        '{file_share}',
        '{storage_account}',
        Sys.getenv('AZURE_STORAGE_KEY')
    )
    system(mount_cmd)

    # Verify mount
    if (!dir.exists('/workspace/MOSAIC/MOSAIC-data')) {{
        stop('Failed to mount Azure File Share')
    }}

    library(MOSAIC)
    set_root_directory('/workspace/MOSAIC')

    # Rest of MOSAIC workflow...
    """
```

Then run with credentials:
```bash
# Source credentials
source azure/storage_mount/.env

# Run on Coiled
python azure/run_mosaic_parallel_country.py \
  --iso ETH \
  --n-simulations 10 \
  --n-iterations 1
```

## Updating Data

When MOSAIC-data gets updated:

```bash
# Re-run the populate script
./02_populate_fileshare.sh

# Workers will see updated data immediately (no rebuild needed!)
```

## Cleanup

To delete the file share (when done testing):

```bash
az storage share delete \
  --account-name ttingeasyva \
  --name mosaic-shared-data
```

## Cost Estimate

Azure Files Standard:
- Storage: 5GB × $0.06/GB/month = $0.30/month
- Transactions: Negligible for small team
- **Total: ~$0.30-0.50/month**

## Troubleshooting

### Mount fails on Coiled workers

Check that workers have cifs-utils:
```bash
# In worker initialization
apt-get update && apt-get install -y cifs-utils
```

### Permission denied

Ensure credentials are passed to workers:
```python
cluster = coiled.Cluster(
    environ={
        'AZURE_STORAGE_ACCOUNT': 'ttingeasyva',
        'AZURE_STORAGE_KEY': storage_key,
        'AZURE_FILE_SHARE': 'mosaic-shared-data'
    }
)
```

### Slow file access

Azure Files in westus2 should be fast since workers are also in westus2. If slow:
- Check network connectivity
- Consider Azure Blob with BlobFuse instead (faster for read-heavy workloads)

## Security Notes

⚠️ **IMPORTANT**:
- Never commit `.env` file with storage keys
- Add `azure/storage_mount/.env` to `.gitignore`
- Rotate storage keys periodically
- Use Azure Key Vault for production

---

**Ready to use!** Run scripts in order, then configure Coiled workers to mount the file share.
