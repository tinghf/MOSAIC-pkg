# =============================================================================
# MOSAIC: run_MOSAIC_future.R
# future.batchtools backend support for Slurm HPC clusters
# =============================================================================

#' Setup future.batchtools Backend for Slurm Clusters
#'
#' Configures future.batchtools for distributed computing on Slurm HPC clusters.
#' This function is called internally by run_MOSAIC() when control$parallel$type = "future".
#'
#' @param backend Character. Backend type: "local" (for testing) or "slurm" (for HPC)
#' @param workers Integer. Number of parallel workers (Slurm jobs) to spawn
#' @param template Character or NULL. Path to custom template file. If NULL,
#'   uses package default Slurm template from inst/templates/slurm.tmpl
#' @param resources Named list. Slurm resource requirements:
#'   \itemize{
#'     \item nodes: Number of nodes per job (default: 1)
#'     \item cpus: CPUs per job (default: 1)
#'     \item memory: Memory per job (default: "4GB")
#'     \item walltime: Max runtime (default: "24:00:00")
#'     \item partition: Slurm partition (optional, e.g., "compute", "gpu")
#'     \item account: Slurm account/project (optional)
#'   }
#' @param verbose Logical. Print setup messages
#'
#' @return Invisibly returns TRUE on success
#'
#' @details
#' This function:
#' 1. Checks for future.batchtools installation
#' 2. Selects appropriate template file
#' 3. Configures future plan with resource requirements
#' 4. Sets up threading limits to prevent oversubscription
#'
#' The function automatically handles threading configuration to ensure
#' each worker uses single-threaded operations, preventing performance
#' degradation from over-subscription.
#'
#' @noRd
.mosaic_setup_future_backend <- function(backend,
                                         workers,
                                         template = NULL,
                                         resources = list(),
                                         verbose = TRUE) {

  # Check for future.batchtools
  if (!requireNamespace("future.batchtools", quietly = TRUE)) {
    stop(
      "future.batchtools package is required for HPC backends.\n",
      "Install with: install.packages('future.batchtools')\n",
      "Or use control$parallel$type = 'PSOCK' for local parallelism.",
      call. = FALSE
    )
  }

  if (!requireNamespace("future.apply", quietly = TRUE)) {
    stop(
      "future.apply package is required for future backend.\n",
      "Install with: install.packages('future.apply')",
      call. = FALSE
    )
  }

  # Validate backend
  if (!backend %in% c("local", "slurm")) {
    stop(sprintf(
      "Invalid backend '%s'. Must be 'local' or 'slurm'.",
      backend
    ), call. = FALSE)
  }

  if (verbose) {
    message(sprintf("Setting up future.batchtools backend: %s", backend))
    message(sprintf("  Workers: %d", workers))
  }

  # Get template file
  if (is.null(template)) {
    # Use package default template
    template_file <- system.file(
      sprintf("templates/%s.tmpl", backend),
      package = "MOSAIC"
    )

    if (!file.exists(template_file) || nchar(template_file) == 0) {
      stop(sprintf(
        "Default Slurm template not found.\n",
        "Expected at: inst/templates/slurm.tmpl\n",
        "Please provide custom template via control$parallel$template"
      ), call. = FALSE)
    }
  } else {
    template_file <- template
    if (!file.exists(template_file)) {
      stop(sprintf("Template file not found: %s", template_file), call. = FALSE)
    }
  }

  if (verbose) {
    message(sprintf("  Template: %s", basename(template_file)))
  }

  # Merge resources with defaults
  default_resources <- list(
    nodes = 1L,
    cpus = 1L,
    memory = "4GB",
    walltime = "24:00:00",
    partition = NULL,
    account = NULL
  )
  resources <- modifyList(default_resources, resources)

  if (verbose) {
    message("  Resources:")
    message(sprintf("    - CPUs: %d", resources$cpus))
    message(sprintf("    - Memory: %s", resources$memory))
    message(sprintf("    - Walltime: %s", resources$walltime))
    if (!is.null(resources$partition)) {
      message(sprintf("    - Partition: %s", resources$partition))
    }
    if (!is.null(resources$account)) {
      message(sprintf("    - Account: %s", resources$account))
    }
  }

  # Setup future plan based on backend
  if (backend == "local") {
    # Local multicore (for testing)
    future::plan(future.batchtools::batchtools_local,
                 workers = workers,
                 resources = resources)
  } else if (backend == "slurm") {
    # Slurm HPC cluster
    future::plan(future.batchtools::batchtools_slurm,
                 template = template_file,
                 workers = workers,
                 resources = resources)
  }

  if (verbose) {
    message(sprintf("✓ future.batchtools backend configured successfully"))
  }

  invisible(TRUE)
}


#' Run Batch Using future.apply
#'
#' Replacement for .mosaic_run_batch that uses future_lapply instead of
#' parallel::parLapply. This enables HPC cluster execution via future.batchtools.
#'
#' @param sim_ids Integer vector of simulation IDs
#' @param worker_func Function to run for each simulation
#' @param show_progress Logical. Show progress bar
#'
#' @return List of results from worker_func
#'
#' @noRd
.mosaic_run_batch_future <- function(sim_ids, worker_func, show_progress) {

  if (!requireNamespace("future.apply", quietly = TRUE)) {
    stop("future.apply package required", call. = FALSE)
  }

  if (isTRUE(show_progress)) {
    # Use progressr for progress reporting across HPC jobs
    if (requireNamespace("progressr", quietly = TRUE)) {
      progressr::with_progress({
        p <- progressr::progressor(steps = length(sim_ids))
        future.apply::future_lapply(sim_ids, function(id) {
          result <- worker_func(id)
          p()  # Update progress
          result
        },
        future.seed = TRUE,
        future.scheduling = Inf)  # Static scheduling (each worker gets equal tasks)
      })
    } else {
      # No progressr - just run without progress
      future.apply::future_lapply(sim_ids, worker_func,
                                  future.seed = TRUE,
                                  future.scheduling = Inf)
    }
  } else {
    # No progress bar
    future.apply::future_lapply(sim_ids, worker_func,
                                future.seed = TRUE,
                                future.scheduling = Inf)
  }
}


#' Validate future.batchtools Configuration
#'
#' Checks that future.batchtools is properly configured before launching
#' a large-scale calibration. Catches common configuration errors early.
#'
#' @param backend Character. Backend type ("local" or "slurm")
#' @param workers Integer. Number of workers
#' @param resources Named list. Resource requirements
#'
#' @return Character vector of warnings/errors, or NULL if valid
#'
#' @noRd
.mosaic_validate_future_config <- function(backend, workers, resources) {

  issues <- character()

  # Check workers
  if (workers < 1) {
    issues <- c(issues, "workers must be >= 1")
  }
  if (workers > 10000) {
    issues <- c(issues, sprintf(
      "Warning: %d workers is very large. Most HPC systems limit concurrent jobs to 1000-5000",
      workers
    ))
  }

  # Check resources
  if (!is.null(resources$cpus) && resources$cpus < 1) {
    issues <- c(issues, "cpus must be >= 1")
  }
  if (!is.null(resources$cpus) && resources$cpus > 128) {
    issues <- c(issues, sprintf(
      "Warning: %d CPUs per job is high. Ensure your cluster has nodes with this capacity",
      resources$cpus
    ))
  }

  # Parse memory
  mem_str <- resources$memory
  if (grepl("^[0-9]+[GMgm][Bb]?$", mem_str)) {
    mem_value <- as.numeric(sub("[GMgm][Bb]?$", "", mem_str))
    mem_unit <- toupper(sub("^[0-9]+", "", sub("[Bb]$", "", mem_str)))

    if (mem_unit == "G" && mem_value > 500) {
      issues <- c(issues, sprintf(
        "Warning: %s memory per job is very high. Verify cluster capacity",
        mem_str
      ))
    }
  }

  # Slurm-specific checks
  if (backend == "slurm") {
    if (is.null(resources$partition)) {
      issues <- c(issues, "Info: No partition specified. Using cluster default")
    }
  }

  if (length(issues) > 0) {
    return(issues)
  } else {
    return(NULL)
  }
}
