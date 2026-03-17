#!/usr/bin/env Rscript
# =============================================================================
# compare_validation_results.R
# =============================================================================
# Compare local vs Dask simulation results using the per-sim
# simresults_*.parquet files in 1_bfrs/outputs/simulation_results/.
# Each file contains per-(sim, iter, j, t) rows with cases, deaths,
# and all sampled parameters.
#
# No cluster or MOSAIC package needed — just arrow + data.table.
#
# Usage:
#   Rscript azure/compare_validation_results.R <local_output_dir> <dask_output_dir>
#
# Example:
#   Rscript azure/compare_validation_results.R \
#     ~/output/validate_local_20260314_034830 \
#     ~/output/validate_dask_20260314_034830
# =============================================================================

library(arrow)
library(data.table)

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 2) {
  # Default to latest matching pair
  base <- path.expand("~/output")
  local_dir <- file.path(base, "validate_local_20260314_034830")
  dask_dir  <- file.path(base, "validate_dask_20260314_034830")
  cat("No arguments — using default paths:\n")
} else {
  local_dir <- args[1]
  dask_dir  <- args[2]
}

local_simresults_dir <- file.path(local_dir, "1_bfrs", "outputs", "simulation_results")
dask_simresults_dir  <- file.path(dask_dir,  "1_bfrs", "outputs", "simulation_results")

cat(sprintf("  Local: %s\n", local_simresults_dir))
cat(sprintf("  Dask:  %s\n\n", dask_simresults_dir))

stopifnot("Local simulation_results dir not found" = dir.exists(local_simresults_dir))
stopifnot("Dask simulation_results dir not found"  = dir.exists(dask_simresults_dir))

# =============================================================================
# LOAD ALL SIMRESULT PARQUETS
# =============================================================================

load_simresults <- function(dir_path) {
  files <- list.files(dir_path, pattern = "^simresults_.*\\.parquet$", full.names = TRUE)
  cat(sprintf("  Found %d parquet files in %s\n", length(files), dir_path))
  if (length(files) == 0) stop("No simresults parquet files found in ", dir_path)
  dt <- rbindlist(lapply(files, function(f) as.data.table(arrow::read_parquet(f))))
  # Ensure key columns are integer
  dt[, sim  := as.integer(sim)]
  dt[, iter := as.integer(iter)]
  dt[, j    := as.integer(j)]
  dt[, t    := as.integer(t)]
  setkey(dt, sim, iter, j, t)
  dt
}

cat("Loading local results...\n")
local_dt <- load_simresults(local_simresults_dir)
cat("Loading Dask results...\n")
dask_dt  <- load_simresults(dask_simresults_dir)

cat(sprintf("\nLocal: %d rows, %d cols, sims %d-%d\n",
            nrow(local_dt), ncol(local_dt),
            min(local_dt$sim), max(local_dt$sim)))
cat(sprintf("Dask:  %d rows, %d cols, sims %d-%d\n",
            nrow(dask_dt), ncol(dask_dt),
            min(dask_dt$sim), max(dask_dt$sim)))

# =============================================================================
# ALIGN ON COMMON SIMS
# =============================================================================

local_sims <- sort(unique(local_dt$sim))
dask_sims  <- sort(unique(dask_dt$sim))
common_sims <- intersect(local_sims, dask_sims)

if (length(common_sims) == 0) stop("No common sim_ids to compare")

if (!identical(local_sims, dask_sims)) {
  cat(sprintf("\n*** WARNING: sim sets differ! Local: %d, Dask: %d, Common: %d ***\n",
              length(local_sims), length(dask_sims), length(common_sims)))
  local_dt <- local_dt[sim %in% common_sims]
  dask_dt  <- dask_dt[sim %in% common_sims]
} else {
  cat(sprintf("\nsim_ids match: %d simulations\n", length(common_sims)))
}

N_SIMS <- length(common_sims)

# Check row counts match per sim
local_counts <- local_dt[, .N, by = sim]
dask_counts  <- dask_dt[, .N, by = sim]
merged_counts <- merge(local_counts, dask_counts, by = "sim", suffixes = c("_local", "_dask"))
row_mismatch <- merged_counts[N_local != N_dask]
if (nrow(row_mismatch) > 0) {
  cat(sprintf("\n*** WARNING: %d sims have different row counts ***\n", nrow(row_mismatch)))
  print(head(row_mismatch, 10))
}

cat("\n=============================================================\n")
cat("  COMPARISON\n")
cat("=============================================================\n\n")

# =============================================================================
# 1. PARAMETER COMPARISON (constant within each sim)
# =============================================================================
cat("--- Parameter comparison ---\n")

# Identify parameter columns (everything except the core result columns)
core_cols  <- c("sim", "iter", "j", "t", "cases", "deaths")
param_cols <- setdiff(names(local_dt), core_cols)
param_cols <- intersect(param_cols, names(dask_dt))

cat(sprintf("  Parameter columns found: %d\n", length(param_cols)))

if (length(param_cols) > 0) {
  # Extract one row per sim for parameter comparison
  local_params <- local_dt[, .SD[1], by = sim, .SDcols = param_cols]
  dask_params  <- dask_dt[, .SD[1], by = sim, .SDcols = param_cols]
  setkey(local_params, sim)
  setkey(dask_params, sim)

  param_max_diffs <- numeric(length(param_cols))
  names(param_max_diffs) <- param_cols

  for (p in param_cols) {
    v_local <- as.numeric(local_params[[p]])
    v_dask  <- as.numeric(dask_params[[p]])
    d <- abs(v_local - v_dask)
    param_max_diffs[p] <- max(d, na.rm = TRUE)
  }

  sorted_diffs <- sort(param_max_diffs, decreasing = TRUE)
  cat("\n  Top 10 parameter discrepancies (max |diff| across sims):\n")
  cat(sprintf("  %-30s  %12s\n", "parameter", "max_abs_diff"))
  cat(sprintf("  %-30s  %12s\n", "------------------------------", "------------"))
  for (i in seq_len(min(10, length(sorted_diffs)))) {
    cat(sprintf("  %-30s  %12.2e\n", names(sorted_diffs)[i], sorted_diffs[i]))
  }

  n_param_exact <- sum(param_max_diffs == 0)
  n_param_close <- sum(param_max_diffs < 1e-10)
  cat(sprintf("\n  Parameters with exact match:    %d / %d\n", n_param_exact, length(param_cols)))
  cat(sprintf("  Parameters with |diff| < 1e-10: %d / %d\n", n_param_close, length(param_cols)))

  # Flag any params with non-trivial differences
  bad_params <- names(param_max_diffs[param_max_diffs >= 1e-10])
  if (length(bad_params) > 0) {
    cat(sprintf("\n  *** %d parameters with |diff| >= 1e-10: %s\n",
                length(bad_params), paste(bad_params, collapse = ", ")))
  }
} else {
  cat("  No parameter columns found in simresults files!\n")
  param_max_diffs <- numeric(0)
}

# =============================================================================
# 1.5. PSI_JT PRECISION ANALYSIS (JSON round-trip float verification)
# =============================================================================
has_psi_jt <- "psi_jt" %in% names(local_dt) && "psi_jt" %in% names(dask_dt)

if (has_psi_jt) {
  cat("\n--- psi_jt precision analysis (JSON round-trip) ---\n")

  psi_merged <- merge(local_dt[, .(sim, iter, j, t, psi_jt)],
                      dask_dt[, .(sim, iter, j, t, psi_jt)],
                      by = c("sim", "iter", "j", "t"),
                      suffixes = c("_local", "_dask"))

  psi_diff     <- psi_merged$psi_jt_local - psi_merged$psi_jt_dask
  psi_abs_diff <- abs(psi_diff)

  n_psi_exact <- sum(psi_diff == 0, na.rm = TRUE)
  n_psi_total <- nrow(psi_merged)

  cat(sprintf("  Rows compared: %d\n", n_psi_total))
  cat(sprintf("  Exact match (diff == 0): %d / %d (%.1f%%)\n",
              n_psi_exact, n_psi_total, 100 * n_psi_exact / n_psi_total))

  if (any(psi_abs_diff > 0, na.rm = TRUE)) {
    nonzero <- psi_abs_diff[psi_abs_diff > 0]
    cat(sprintf("  Abs diff — max: %.2e  mean: %.2e  median: %.2e\n",
                max(nonzero), mean(nonzero), median(nonzero)))

    # Relative diff (avoid div-by-zero)
    psi_rel_diff <- ifelse(
      abs(psi_merged$psi_jt_local) > 0,
      psi_abs_diff / abs(psi_merged$psi_jt_local),
      NA_real_
    )
    finite_rel <- psi_rel_diff[is.finite(psi_rel_diff) & psi_rel_diff > 0]
    if (length(finite_rel) > 0) {
      cat(sprintf("  Rel diff — max: %.2e  mean: %.2e  median: %.2e\n",
                  max(finite_rel), mean(finite_rel), median(finite_rel)))
    }

    # ULP estimate: |diff| / (eps * |value|)  where eps = 2.220446e-16
    eps <- .Machine$double.eps
    ulp_est <- ifelse(
      abs(psi_merged$psi_jt_local) > 0,
      psi_abs_diff / (eps * abs(psi_merged$psi_jt_local)),
      NA_real_
    )
    finite_ulp <- ulp_est[is.finite(ulp_est) & ulp_est > 0]
    if (length(finite_ulp) > 0) {
      cat(sprintf("  ULP estimate — max: %.1f  mean: %.1f  median: %.1f\n",
                  max(finite_ulp), mean(finite_ulp), median(finite_ulp)))
      cat(sprintf("  (1.0 = exactly 1 ULP of float64 precision)\n"))
    }
  } else {
    cat("  All psi_jt values match exactly (no JSON precision loss detected)\n")
  }
} else {
  cat("\n--- psi_jt precision analysis: SKIPPED (column not found in simresults) ---\n")
  psi_merged <- NULL
}

# =============================================================================
# 2. SIMULATION RESULTS COMPARISON (cases & deaths)
# =============================================================================
cat("\n--- Simulation results comparison (cases & deaths) ---\n")

# Inner join on (sim, iter, j, t)
merged <- merge(local_dt[, .(sim, iter, j, t, cases, deaths)],
                dask_dt[, .(sim, iter, j, t, cases, deaths)],
                by = c("sim", "iter", "j", "t"),
                suffixes = c("_local", "_dask"))

cat(sprintf("  Matched rows: %d (local: %d, dask: %d)\n",
            nrow(merged), nrow(local_dt), nrow(dask_dt)))

unmatched_local <- nrow(local_dt) - nrow(merged)
unmatched_dask  <- nrow(dask_dt) - nrow(merged)
if (unmatched_local > 0 || unmatched_dask > 0) {
  cat(sprintf("  *** Unmatched rows: %d local, %d dask ***\n",
              unmatched_local, unmatched_dask))
}

# --- Cases ---
cat("\n  [Cases]\n")
cases_diff     <- merged$cases_local - merged$cases_dask
cases_abs_diff <- abs(cases_diff)
cases_rel_diff <- ifelse(
  is.finite(merged$cases_local) & merged$cases_local != 0,
  abs(cases_diff / merged$cases_local),
  NA_real_
)

n_cases_exact <- sum(cases_diff == 0, na.rm = TRUE)
n_cases_close <- sum(cases_abs_diff < 1e-6, na.rm = TRUE)
n_cases_total <- nrow(merged)

cat(sprintf("    Exact match (diff == 0):     %d / %d (%.1f%%)\n",
            n_cases_exact, n_cases_total, 100 * n_cases_exact / n_cases_total))
cat(sprintf("    Close match (|diff| < 1e-6): %d / %d (%.1f%%)\n",
            n_cases_close, n_cases_total, 100 * n_cases_close / n_cases_total))

if (any(cases_abs_diff > 0, na.rm = TRUE)) {
  cat(sprintf("    Abs diff — max: %.2e  mean: %.2e  median: %.2e\n",
              max(cases_abs_diff, na.rm = TRUE),
              mean(cases_abs_diff, na.rm = TRUE),
              median(cases_abs_diff, na.rm = TRUE)))
  finite_rel <- cases_rel_diff[is.finite(cases_rel_diff) & cases_rel_diff > 0]
  if (length(finite_rel) > 0) {
    cat(sprintf("    Rel diff — max: %.2e  mean: %.2e  median: %.2e\n",
                max(finite_rel), mean(finite_rel), median(finite_rel)))
  }
}

# --- Deaths ---
cat("\n  [Deaths]\n")
deaths_diff     <- merged$deaths_local - merged$deaths_dask
deaths_abs_diff <- abs(deaths_diff)
deaths_rel_diff <- ifelse(
  is.finite(merged$deaths_local) & merged$deaths_local != 0,
  abs(deaths_diff / merged$deaths_local),
  NA_real_
)

n_deaths_exact <- sum(deaths_diff == 0, na.rm = TRUE)
n_deaths_close <- sum(deaths_abs_diff < 1e-6, na.rm = TRUE)

cat(sprintf("    Exact match (diff == 0):     %d / %d (%.1f%%)\n",
            n_deaths_exact, n_cases_total, 100 * n_deaths_exact / n_cases_total))
cat(sprintf("    Close match (|diff| < 1e-6): %d / %d (%.1f%%)\n",
            n_deaths_close, n_cases_total, 100 * n_deaths_close / n_cases_total))

if (any(deaths_abs_diff > 0, na.rm = TRUE)) {
  cat(sprintf("    Abs diff — max: %.2e  mean: %.2e  median: %.2e\n",
              max(deaths_abs_diff, na.rm = TRUE),
              mean(deaths_abs_diff, na.rm = TRUE),
              median(deaths_abs_diff, na.rm = TRUE)))
  finite_rel <- deaths_rel_diff[is.finite(deaths_rel_diff) & deaths_rel_diff > 0]
  if (length(finite_rel) > 0) {
    cat(sprintf("    Rel diff — max: %.2e  mean: %.2e  median: %.2e\n",
                max(finite_rel), mean(finite_rel), median(finite_rel)))
  }
}

# =============================================================================
# 3. PER-SIM SUMMARY
# =============================================================================
cat("\n--- Per-sim summary ---\n")

per_sim <- merged[, .(
  cases_max_abs    = max(abs(cases_local - cases_dask), na.rm = TRUE),
  cases_mean_abs   = mean(abs(cases_local - cases_dask), na.rm = TRUE),
  deaths_max_abs   = max(abs(deaths_local - deaths_dask), na.rm = TRUE),
  deaths_mean_abs  = mean(abs(deaths_local - deaths_dask), na.rm = TRUE),
  n_rows           = .N
), by = sim]

setkey(per_sim, sim)

cat(sprintf("\n  %7s  %12s  %12s  %12s  %12s  %6s\n",
            "sim", "cases_max", "cases_mean", "deaths_max", "deaths_mean", "rows"))
cat(sprintf("  %7s  %12s  %12s  %12s  %12s  %6s\n",
            "-------", "------------", "------------",
            "------------", "------------", "------"))
for (i in seq_len(nrow(per_sim))) {
  cat(sprintf("  %7d  %12.2e  %12.2e  %12.2e  %12.2e  %6d\n",
              per_sim$sim[i],
              per_sim$cases_max_abs[i], per_sim$cases_mean_abs[i],
              per_sim$deaths_max_abs[i], per_sim$deaths_mean_abs[i],
              per_sim$n_rows[i]))
}

# =============================================================================
# 4. WORST MISMATCHES (top 10 rows by cases abs diff)
# =============================================================================
if (any(cases_abs_diff > 0, na.rm = TRUE)) {
  cat("\n--- Top 10 worst case mismatches ---\n")
  merged[, cases_abs_diff := abs(cases_local - cases_dask)]
  worst <- merged[order(-cases_abs_diff)][1:min(10, nrow(merged))]
  cat(sprintf("  %5s  %4s  %3s  %5s  %14s  %14s  %12s\n",
              "sim", "iter", "j", "t", "cases_local", "cases_dask", "abs_diff"))
  cat(sprintf("  %5s  %4s  %3s  %5s  %14s  %14s  %12s\n",
              "-----", "----", "---", "-----",
              "--------------", "--------------", "------------"))
  for (i in seq_len(nrow(worst))) {
    cat(sprintf("  %5d  %4d  %3d  %5d  %14.4f  %14.4f  %12.2e\n",
                worst$sim[i], worst$iter[i], worst$j[i], worst$t[i],
                worst$cases_local[i], worst$cases_dask[i],
                worst$cases_abs_diff[i]))
  }
}

# =============================================================================
# VERDICT
# =============================================================================
cat("\n=============================================================\n")

all_params_match  <- length(param_cols) == 0 || all(param_max_diffs < 1e-10)
all_cases_match   <- n_cases_exact == n_cases_total
all_deaths_match  <- n_deaths_exact == n_cases_total
cases_close       <- n_cases_close == n_cases_total
deaths_close      <- n_deaths_close == n_cases_total
no_unmatched      <- unmatched_local == 0 && unmatched_dask == 0

if (all_params_match && all_cases_match && all_deaths_match && no_unmatched) {
  cat("  PASS: local and Dask produce identical simulation results\n")
} else if (all_params_match && cases_close && deaths_close && no_unmatched) {
  cat("  PASS (NEAR-EXACT): cases/deaths within 1e-6, params match\n")
  cat("  (Small float diffs likely from JSON round-trip or numpy precision)\n")
} else {
  cat("  FAIL: results differ between local and Dask paths\n")
  if (!all_params_match)  cat("    - Parameter value mismatch\n")
  if (!all_cases_match)   cat(sprintf("    - Cases mismatch (%d / %d exact)\n",
                                      n_cases_exact, n_cases_total))
  if (!all_deaths_match)  cat(sprintf("    - Deaths mismatch (%d / %d exact)\n",
                                      n_deaths_exact, n_cases_total))
  if (!no_unmatched)      cat("    - Row count mismatch between local and Dask\n")
}
cat("=============================================================\n")

# Save comparison CSV (with psi_jt columns if available)
summary_file <- file.path(local_dir, "validation_comparison.csv")
out_df <- merged[, .(sim, iter, j, t,
                     cases_local, cases_dask,
                     cases_diff = cases_local - cases_dask,
                     deaths_local, deaths_dask,
                     deaths_diff = deaths_local - deaths_dask)]

if (!is.null(psi_merged)) {
  psi_cols <- psi_merged[, .(sim, iter, j, t,
                             psi_jt_local, psi_jt_dask,
                             psi_jt_diff = psi_jt_local - psi_jt_dask)]
  out_df <- merge(out_df, psi_cols, by = c("sim", "iter", "j", "t"), all.x = TRUE)
}

fwrite(out_df, summary_file)
cat(sprintf("\nSaved detailed comparison: %s\n", summary_file))
