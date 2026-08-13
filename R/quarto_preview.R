quarto_executable <- function() {
  executable <- Sys.which("quarto")
  if (!nzchar(executable)) {
    stop(
      paste(
        "Could not find the Quarto CLI.",
        "Install Quarto and ensure `quarto` is available on PATH."
      ),
      call. = FALSE
    )
  }
  unname(executable)
}

quarto_preview_port <- function(lines) {
  if (!length(lines)) {
    return(NULL)
  }

  lines <- lines[grepl("Browse at", lines, fixed = TRUE)]
  if (!length(lines)) {
    return(NULL)
  }

  matches <- regexec(
    "https?://(?:\\[[^]]+\\]|[^:/[:space:]]+):([0-9]+)",
    lines,
    perl = TRUE
  )
  values <- regmatches(lines, matches)
  values <- values[lengths(values) == 2L]

  if (!length(values)) {
    return(NULL)
  }

  port <- suppressWarnings(as.integer(values[[length(values)]][[2L]]))
  if (is.na(port)) NULL else port
}

#' Preview a Quarto document with live rendering
#'
#' Starts `quarto preview` in a managed background process. Quarto watches the
#' document and its resources, renders saved changes, and reloads connected
#' browsers. The returned object can be managed with `$stop()`, `$start()`, and
#' `$restart()` just like the object returned by [serve_file()].
#' The Quarto CLI must be installed and available on `PATH`.
#'
#' Rendering a Quarto document can execute code embedded in that document. Only
#' preview documents that you trust.
#'
#' @param file Path to a `.qmd` file. When omitted in RStudio, the active saved
#'   source document is used.
#' @param host Address on which Quarto listens. Use `"0.0.0.0"` for viewers on
#'   the same local network.
#' @param port Preferred TCP port, from 1 through 65535. Quarto can select a
#'   different port when this one is unavailable; the server's `$url` updates
#'   when the actual preview URL is reported.
#' @param open_browser Open the preview after Quarto reports that it is ready.
#' @param auto_save Automatically save the document when it is open in RStudio,
#'   so unsaved editor changes can be rendered.
#' @param interval Interval in seconds between RStudio auto-save checks.
#' @param to Quarto output format. The default, `"html"`, is suitable for browser
#'   preview. Other browser-previewable formats such as `"revealjs"` can also be
#'   used.
#' @param cache Use Quarto's execution cache so unchanged chunks can reuse their
#'   previous results. Set to `FALSE` to bypass stored results during preview
#'   renders.
#'
#' @return A `QuartoPreviewServer` object, invisibly.
#' @export
preview_qmd <- function(file = NULL, host = "127.0.0.1", port = 3000L,
                        open_browser = interactive(), auto_save = TRUE,
                        interval = 0.75, to = "html", cache = TRUE) {
  if (!is.logical(auto_save) || length(auto_save) != 1L || is.na(auto_save)) {
    stop("`auto_save` must be `TRUE` or `FALSE`.", call. = FALSE)
  }
  if (!is.logical(open_browser) || length(open_browser) != 1L ||
      is.na(open_browser)) {
    stop("`open_browser` must be `TRUE` or `FALSE`.", call. = FALSE)
  }
  if (!is.logical(cache) || length(cache) != 1L || is.na(cache)) {
    stop("`cache` must be `TRUE` or `FALSE`.", call. = FALSE)
  }

  source <- resolve_stream_source(file, auto_save)
  file <- source$path

  if (!file.exists(file)) {
    stop(sprintf("File does not exist: %s", file), call. = FALSE)
  }
  if (dir.exists(file)) {
    stop(sprintf("`file` must not be a directory: %s", file), call. = FALSE)
  }
  if (!identical(tolower(tools::file_ext(file)), "qmd")) {
    stop("`file` must have a .qmd extension.", call. = FALSE)
  }
  if (!is.character(host) || length(host) != 1L || !nzchar(host)) {
    stop("`host` must be one non-empty address.", call. = FALSE)
  }

  port <- suppressWarnings(as.integer(port))
  if (length(port) != 1L || is.na(port) || port < 1L || port > 65535L) {
    stop("`port` must be an integer from 1 through 65535.", call. = FALSE)
  }

  interval <- suppressWarnings(as.numeric(interval))
  if (length(interval) != 1L || is.na(interval) || !is.finite(interval) ||
      interval <= 0) {
    stop("`interval` must be one positive number of seconds.", call. = FALSE)
  }
  if (!is.character(to) || length(to) != 1L || !nzchar(to)) {
    stop("`to` must be one non-empty Quarto format.", call. = FALSE)
  }
  invisible(QuartoPreviewServer$new(
    path = file,
    host = host,
    port = port,
    interval = interval,
    to = to,
    cache = cache,
    open_browser = open_browser,
    document_id = source$document_id,
    quarto = quarto_executable()
  ))
}

#' A managed Quarto preview process
#'
#' This class is returned by [preview_qmd()].
#'
#' @param path Normalized path to the `.qmd` file.
#' @param host Address on which Quarto listens.
#' @param port Preferred TCP port.
#' @param interval RStudio auto-save interval in seconds.
#' @param to Quarto output format.
#' @param cache Whether to use Quarto's execution cache.
#' @param open_browser Whether to open the preview when it is ready.
#' @param document_id Optional RStudio document identifier to auto-save.
#' @param quarto Path to the Quarto executable.
#'
#' @keywords internal
QuartoPreviewServer <- R6::R6Class(
  "QuartoPreviewServer",
  cloneable = FALSE,
  private = list(
    file_path = NULL,
    bind_host = NULL,
    preferred_port = NULL,
    actual_port = NULL,
    interval = NULL,
    format = NULL,
    cache = TRUE,
    document_id = NULL,
    quarto = NULL,
    process = NULL,
    open_browser = FALSE,
    browser_opened = FALSE,
    generation = 0L,
    log_lines = character(),
    exit_status = NULL,
    last_save_error = NULL,

    append_log = function(lines) {
      if (length(lines)) {
        private$log_lines <- tail(c(private$log_lines, lines), 200L)
      }
      invisible(NULL)
    },

    handle_output = function(lines) {
      private$append_log(lines)

      detected_port <- quarto_preview_port(lines)
      if (is.null(detected_port)) {
        return(invisible(NULL))
      }

      first_ready <- is.null(private$actual_port)
      private$actual_port <- detected_port

      if (first_ready) {
        message(sprintf(
          "Quarto preview ready for '%s' at %s",
          basename(private$file_path),
          self$url
        ))
      }
      if (isTRUE(private$open_browser) && !private$browser_opened) {
        private$browser_opened <- TRUE
        tryCatch(
          utils::browseURL(self$url),
          error = function(error) warning(conditionMessage(error), call. = FALSE)
        )
      }

      invisible(NULL)
    },

    read_output = function() {
      if (is.null(private$process)) {
        return(character())
      }
      tryCatch(
        private$process$read_output_lines(),
        error = function(error) character()
      )
    },

    terminate_process = function() {
      if (is.null(private$process) || !private$process$is_alive()) {
        return(invisible(FALSE))
      }

      tryCatch(
        private$process$kill_tree(),
        error = function(error) private$process$kill()
      )
      invisible(TRUE)
    },

    monitor = function(generation) {
      if (!identical(generation, private$generation) ||
          is.null(private$process)) {
        return(invisible(NULL))
      }

      lines <- private$read_output()
      private$handle_output(lines)

      if (private$process$is_alive()) {
        later::later(function() private$monitor(generation), delay = 0.2)
      } else {
        private$append_log(private$read_output())
        private$exit_status <- private$process$get_exit_status()
        deregister_server(self)
        if (!identical(private$exit_status, 0L)) {
          warning(
            sprintf(
              "Quarto preview exited with status %s. Call `$logs()` for details.",
              private$exit_status
            ),
            call. = FALSE
          )
        }
      }

      invisible(NULL)
    },

    auto_save = function(generation) {
      if (!identical(generation, private$generation) ||
          is.null(private$document_id) || !self$is_running()) {
        return(invisible(NULL))
      }

      error <- tryCatch(
        {
          rstudioapi::documentSave(private$document_id)
          NULL
        },
        error = identity
      )
      if (is.null(error)) {
        private$last_save_error <- NULL
      } else if (!identical(conditionMessage(error), private$last_save_error)) {
        private$last_save_error <- conditionMessage(error)
        warning(
          sprintf("Could not auto-save the Quarto document: %s",
                  private$last_save_error),
          call. = FALSE
        )
      }

      later::later(function() private$auto_save(generation),
                   delay = private$interval)
      invisible(NULL)
    },

    finalize = function() {
      if (!is.null(private$process) && private$process$is_alive()) {
        private$terminate_process()
      }
    }
  ),
  public = list(
    #' @description Create and start a managed Quarto preview.
    initialize = function(path, host, port, interval, to, cache, open_browser,
                          document_id, quarto) {
      private$file_path <- normalizePath(path, mustWork = TRUE)
      private$bind_host <- host
      private$preferred_port <- port
      private$interval <- interval
      private$format <- to
      private$cache <- cache
      private$open_browser <- open_browser
      private$document_id <- document_id
      private$quarto <- quarto
      self$start()
    },

    #' @description Start the preview if it is stopped.
    start = function() {
      if (self$is_running()) {
        return(invisible(self))
      }

      private$generation <- private$generation + 1L
      generation <- private$generation
      private$actual_port <- NULL
      private$browser_opened <- FALSE
      private$log_lines <- character()
      private$exit_status <- NULL

      args <- c(
        "preview",
        private$file_path,
        "--to", private$format,
        "--host", private$bind_host,
        "--port", as.character(private$preferred_port),
        "--no-browser"
      )
      if (isTRUE(private$cache)) {
        args <- c(args, "--cache")
      } else {
        args <- c(args, "--no-cache")
      }

      private$process <- tryCatch(
        process$new(
          command = private$quarto,
          args = args,
          stdout = "|",
          stderr = "2>&1",
          cleanup = TRUE,
          cleanup_tree = FALSE
        ),
        error = function(error) {
          stop(
            sprintf("Could not start Quarto preview: %s",
                    conditionMessage(error)),
            call. = FALSE
          )
        }
      )

      register_server(self)
      message(sprintf("Starting Quarto preview for '%s'...",
                      basename(private$file_path)))
      later::later(function() private$monitor(generation), delay = 0)
      if (!is.null(private$document_id)) {
        later::later(function() private$auto_save(generation),
                     delay = private$interval)
      }

      invisible(self)
    },

    #' @description Stop the Quarto process.
    stop = function() {
      private$generation <- private$generation + 1L
      was_running <- self$is_running()
      if (was_running) {
        private$terminate_process()
        private$process$wait(timeout = 2000)
      }
      private$append_log(private$read_output())
      private$process <- NULL
      deregister_server(self)

      if (was_running) {
        message(sprintf("Stopped Quarto preview at %s", self$url))
      }
      invisible(self)
    },

    #' @description Stop and then start the preview.
    restart = function() {
      self$stop()
      self$start()
    },

    #' @description Report whether the Quarto process is running.
    is_running = function() {
      !is.null(private$process) && isTRUE(private$process$is_alive())
    },

    #' @description Return up to 200 of the most recent Quarto log lines.
    logs = function() {
      private$handle_output(private$read_output())
      private$log_lines
    },

    #' @description Print the preview status, file, and URL.
    #' @param ... Unused.
    print = function(...) {
      status <- if (self$is_running()) "running" else "stopped"
      cat(sprintf(
        "<livecodeR Quarto preview: %s>\n  file: %s\n  url:  %s\n",
        status,
        private$file_path,
        self$url
      ))
      invisible(self)
    }
  ),
  active = list(
    #' @field url Local URL for the rendered preview.
    url = function() {
      display_host <- if (identical(private$bind_host, "0.0.0.0")) {
        "127.0.0.1"
      } else {
        private$bind_host
      }
      port <- if (is.null(private$actual_port)) {
        private$preferred_port
      } else {
        private$actual_port
      }
      sprintf("http://%s:%d", display_host, port)
    },

    #' @field path Absolute path to the `.qmd` file.
    path = function() private$file_path,
    #' @field host Listening address.
    host = function() private$bind_host,
    #' @field port Actual preview port once known, otherwise the preferred port.
    port = function() {
      if (is.null(private$actual_port)) private$preferred_port else private$actual_port
    }
  )
)
