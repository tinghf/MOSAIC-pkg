# Dask Scale-Out: Troubleshooting Session (2026-03-12)

Issues investigated and resolved while scaling MOSAIC BFRS calibration to 20K-40K simulations across 200 Coiled workers.

---

## 1. Docker Hub Pull Rate Limits

**Problem:** Coiled workers hitting `"You have reached your unauthenticated pull rate limit"` when pulling `ttingidmod/mosaic-worker:latest` from Docker Hub.

**Solution:** Migrated to Azure Container Registry (ACR):
- Created `idmmosaicacr.azurecr.io` (Standard tier, westus2)
- Enabled anonymous pull (no auth needed, no rate limits)
- Created Coiled software env `mosaic-acr-workers` pointing to ACR image
- Updated `run_MOSAIC_dask.R` default from `mosaic-docker-workers` → `mosaic-acr-workers`

## 2. Docker Hub Auth Fallback

**Added but superseded by ACR:** Added `docker_login` and `environ` support to `dask_spec` in `run_MOSAIC_dask.R`, auto-forwarding `DOCKER_USERNAME`/`DOCKER_PASSWORD` env vars to Coiled workers.

## 3. TLS Disconnection During Post-Processing

**Problem:** `CommClosedError` — Dask client lost TLS connection to scheduler and failed to reconnect within 30 seconds, crashing the run.

**Root Cause:** The connection drops because the R process blocks the Python event loop during long R-side work. Since `reticulate` shares the main thread between R and Python, any long-running R computation prevents the Dask Tornado event loop from sending heartbeat messages. The scheduler eventually considers the client dead and drops the connection. The critical sections vulnerable to this are:

- **Likelihood loop** in `.mosaic_run_batch_dask()` — the `for (idx in ...)` loop computing likelihoods + writing parquet for each sim. With batch_size=20,000 this loop runs for ~20 minutes with no Python event loop activity.
- **Post-processing parquet load** in the main function — loading/combining all parquet files into a single data frame (~2 min for 20K files).
- **ESS + subset optimization + weight computation** — additional heavy R-side work after combining results.

**Solution:** Close the Dask client/cluster *before* post-processing starts. All worker results are already gathered at that point — Dask is no longer needed. This also stops billing for Coiled workers sooner. Added diagnostic logging (scheduler ping every 500 sims, timing at each stage, memory reporting) to detect and diagnose any future connection issues.

## 4. Scheduler VM Too Small

**Problem:** Scheduler was hardcoded to same VM type as workers (`Standard_D2s_v6`, 8 GB).

**Solution:** Added separate `dask_spec$scheduler_vm_types` field, defaulting to `Standard_D4s_v6` (16 GB).

## 5. OOM Kill During Parquet Loading

**Problem:** R process killed by kernel at ~8.3 GB RSS while loading 19,999 parquet files. Silent exit (no R error). Confirmed via `dmesg` showing OOM kill of the R process inside the Docker container.

**Solution (iterative):**
- First: added `rm()` + `gc()` after batch function returns — not enough
- Second: added `result_lookup[key] <- list(NULL)` and `params_list[idx] <- list(NULL)` *inside* the likelihood loop to free each sim's data immediately after processing
- Added `gc()` + memory logging before post-processing

## 6. `subscript out of bounds` Bug

**Problem:** `params_list[[idx]] <- NULL` removes the element and shrinks the list in R, shifting all subsequent indices.

**Fix:** Changed to `params_list[idx] <- list(NULL)` (sets to NULL in-place, preserving list length).

## 7. Arrow `open_dataset()` OOM on 40K Parquet Files

**Problem:** `arrow::open_dataset() %>% collect()` OOM-killed the R process when loading 40K single-row parquet files (795 MB on disk, but ~10 GB in memory due to per-file metadata overhead). The "streaming" label is misleading — `collect()` materializes everything at once. Parquet is designed for few large files, not thousands of tiny ones.

**Solution:** Replaced `open_dataset() %>% collect()` with chunked loading: read files in batches of N using `arrow::read_parquet()` + `data.table::rbindlist()`, then combine chunks. Chunk size is configurable via `control$io$load_chunk_size` (default 5000). This bounds peak memory to one chunk at a time.

**Affected files:** `R/run_MOSAIC_helpers.R` (`.mosaic_load_and_combine_results()`), `R/run_MOSAIC.R` and `R/run_MOSAIC_dask.R` (callers), `mosaic_control_defaults()` (new `load_chunk_size` io setting).

**Note:** The root cause is writing one parquet per simulation — 40K single-row files is pathological for any reader. A longer-term fix would be batching rows into fewer, larger parquet files.

## 8. Diagnostic Logging Added (throughout session)

Added timing/progress logs at key points in `run_MOSAIC_dask.R`:
- Gather elapsed time
- Likelihood loop progress every 500 sims + scheduler ping
- Likelihood throughput (sims/s)
- Memory usage before post-processing
- Dask client health check

## 9. WSL2 Memory Limit

**Problem:** WSL2 defaults to 50% of host RAM (~16 GB on a 32 GB laptop). Insufficient for 40K+ sim runs even with chunked loading.

**Solution:** Increase WSL2 memory in `C:\Users\<username>\.wslconfig`:
```
[wsl2]
memory=20GB
```
Then `wsl --shutdown` and restart.

## 10. Orchestrator VM Sizing

**Analysis:** Local WSL2 is I/O bound (100% disk) + memory constrained (93%). Recommended `Standard_E4s_v6` (4 vCPU, 32 GB, memory-optimized) for running the orchestrator Docker container on Azure.

## 11. Housekeeping

- Created `azure/ACR_SETUP.md` documenting the full ACR setup
- Moved test script from `/tmp/mosaic_dask_test.R` to `azure/mosaic_dask_test.R`
- Updated docker run command to use ACR image + mounted script path
- Updated `azure/MOSAIC_DASK_GUIDE.md` and `azure/DOCKER_COILED_SUMMARY.md` with new image/env references

---

## Files Modified

| File | Changes |
|------|---------|
| `R/run_MOSAIC_dask.R` | ACR default, `scheduler_vm_types`, `docker_login`/`environ`, incremental memory freeing, diagnostic logging, early Dask close, chunked parquet loading |
| `R/run_MOSAIC_helpers.R` | Chunked parquet loading in `.mosaic_load_and_combine_results()`, configurable `chunk_size` parameter |
| `R/run_MOSAIC.R` | Pass `load_chunk_size` to parquet loader, new `load_chunk_size` in `mosaic_control_defaults()` io settings |
| `azure/ACR_SETUP.md` | New — full ACR setup documentation |
| `azure/mosaic_dask_test.R` | New — test script (moved from `/tmp`) |
| `azure/mosaic_dask_fixed_test.R` | New — fixed-mode test (large batch) |
| `azure/mosaic_dask_adaptive_test.R` | New — adaptive-mode test (multi-batch) |
| `azure/MOSAIC_DASK_GUIDE.md` | Updated image refs, docker run command, Coiled env name |
| `azure/DOCKER_COILED_SUMMARY.md` | Updated image refs, Coiled env name |
