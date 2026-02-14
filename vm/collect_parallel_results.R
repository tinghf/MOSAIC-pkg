#!/usr/bin/env Rscript
# ==============================================================================
# Collect Results from Parallel Country Runs
# ==============================================================================
# After running countries independently, use this script to:
# 1. Check which countries completed successfully
# 2. Aggregate convergence diagnostics
# 3. Create summary tables
# ==============================================================================

library(MOSAIC)

# Define countries that were run
countries <- c("MOZ", "MWI", "ZMB", "ZWE", "TZA", "KEN", "ETH", "SOM")

# Base output directory
base_dir <- path.expand("~/MOSAIC/output")

cat("==============================================================================\n")
cat("Collecting Results from Parallel MOSAIC Runs\n")
cat("==============================================================================\n\n")

# Check completion status
status_df <- data.frame(
  country = character(),
  completed = logical(),
  has_simulations = logical(),
  n_simulations = numeric(),
  output_size_mb = numeric(),
  stringsAsFactors = FALSE
)

for (iso in countries) {
  dir_output <- file.path(base_dir, iso)

  cat("Checking:", iso, "\n")

  # Check if directory exists
  if (!dir.exists(dir_output)) {
    status_df <- rbind(status_df, data.frame(
      country = iso,
      completed = FALSE,
      has_simulations = FALSE,
      n_simulations = 0,
      output_size_mb = 0
    ))
    cat("  Status: NOT STARTED\n\n")
    next
  }

  # Check for simulation results
  sim_file <- file.path(dir_output, "1_bfrs", "outputs", "simulations.parquet")

  if (file.exists(sim_file)) {
    # Try to read simulations
    tryCatch({
      sims <- arrow::read_parquet(sim_file)
      n_sims <- nrow(sims)

      # Calculate directory size
      all_files <- list.files(dir_output, recursive = TRUE, full.names = TRUE)
      dir_size <- sum(file.size(all_files)) / 1024^2  # MB

      status_df <- rbind(status_df, data.frame(
        country = iso,
        completed = TRUE,
        has_simulations = TRUE,
        n_simulations = n_sims,
        output_size_mb = round(dir_size, 2)
      ))

      cat("  Status: COMPLETED\n")
      cat("  Simulations:", n_sims, "\n")
      cat("  Directory size:", round(dir_size, 2), "MB\n\n")

    }, error = function(e) {
      status_df <- rbind(status_df, data.frame(
        country = iso,
        completed = FALSE,
        has_simulations = TRUE,
        n_simulations = 0,
        output_size_mb = 0
      ))
      cat("  Status: INCOMPLETE (simulation file exists but unreadable)\n\n")
    })
  } else {
    # Directory exists but no results yet
    all_files <- list.files(dir_output, recursive = TRUE, full.names = TRUE)
    dir_size <- ifelse(length(all_files) > 0, sum(file.size(all_files)) / 1024^2, 0)

    status_df <- rbind(status_df, data.frame(
      country = iso,
      completed = FALSE,
      has_simulations = FALSE,
      n_simulations = 0,
      output_size_mb = round(dir_size, 2)
    ))
    cat("  Status: IN PROGRESS\n")
    cat("  Directory size:", round(dir_size, 2), "MB\n\n")
  }
}

# Print summary table
cat("==============================================================================\n")
cat("Summary\n")
cat("==============================================================================\n")
print(status_df, row.names = FALSE)

# Calculate totals
n_completed <- sum(status_df$completed)
n_total <- nrow(status_df)
total_sims <- sum(status_df$n_simulations)
total_size_gb <- sum(status_df$output_size_mb) / 1024

cat("\n")
cat("Completed:", n_completed, "/", n_total, "countries\n")
cat("Total simulations:", total_sims, "\n")
cat("Total output size:", round(total_size_gb, 2), "GB\n")
cat("==============================================================================\n")

# Save status table
status_file <- file.path(base_dir, "parallel_run_status.csv")
write.csv(status_df, status_file, row.names = FALSE)
cat("\nStatus table saved to:", status_file, "\n")
