make_stream_app <- function(path, interval) {
  cache <- file_cache(path)
  page <- render_template(
    pkg_resource("templates", "prism.html"),
    basename(path)
  )

  sockets <- new.env(parent = emptyenv())
  next_socket_id <- 0L
  monitor_running <- FALSE
  monitor_enabled <- TRUE
  last_broadcast_revision <- cache$state()[["revision"]]
  last_error <- NULL

  websocket_state <- function(client_revision = NULL) {
    tryCatch(
      c(cache$state(client_revision), list(interval = interval)),
      error = function(error) list(
        changed = FALSE,
        interval = interval,
        error = conditionMessage(error)
      )
    )
  }

  send_state <- function(socket_id, state) {
    socket <- sockets[[socket_id]]
    if (is.null(socket)) {
      return(invisible(FALSE))
    }

    sent <- tryCatch(
      {
        socket$send(jsonlite::toJSON(
          state,
          auto_unbox = TRUE,
          null = "null"
        ))
        TRUE
      },
      error = function(error) FALSE
    )

    if (!sent && exists(socket_id, envir = sockets, inherits = FALSE)) {
      rm(list = socket_id, envir = sockets)
    }

    invisible(sent)
  }

  broadcast <- function(state) {
    for (socket_id in ls(sockets, all.names = TRUE)) {
      send_state(socket_id, state)
    }
    invisible(NULL)
  }

  monitor_file <- function() {
    if (!monitor_enabled || length(sockets) == 0L) {
      monitor_running <<- FALSE
      return(invisible(NULL))
    }

    state <- websocket_state(last_broadcast_revision)

    if (!is.null(state$error)) {
      if (!identical(state$error, last_error)) {
        broadcast(state)
        last_error <<- state$error
      }
    } else {
      last_error <<- NULL
      if (isTRUE(state$changed)) {
        last_broadcast_revision <<- state$revision
        broadcast(state)
      }
    }

    later::later(monitor_file, interval)
    invisible(NULL)
  }

  start_monitor <- function() {
    if (!monitor_running && monitor_enabled) {
      monitor_running <<- TRUE
      later::later(monitor_file, interval)
    }
    invisible(NULL)
  }

  app <- list(
    call = function(request) {
      request_path <- request$PATH_INFO

      if (identical(request_path, "/")) {
        return(text_response(
          page,
          content_type = "text/html; charset=UTF-8"
        ))
      }

      if (identical(request_path, "/__livecode__/poll")) {
        revision <- client_revision(request$QUERY_STRING)
        return(json_response(websocket_state(revision)))
      }

      text_response("Not found", status = 404L)
    },

    onWSOpen = function(socket) {
      if (!identical(socket$request$PATH_INFO, "/__livecode__/ws")) {
        socket$close(1008L, "Unknown WebSocket endpoint")
        return(invisible(NULL))
      }

      next_socket_id <<- next_socket_id + 1L
      socket_id <- sprintf("socket-%08d", next_socket_id)
      sockets[[socket_id]] <- socket

      socket$onClose(function() {
        if (exists(socket_id, envir = sockets, inherits = FALSE)) {
          rm(list = socket_id, envir = sockets)
        }
      })

      send_state(socket_id, websocket_state())
      start_monitor()
    },

    staticPaths = list(
      "/web" = httpuv::staticPath(pkg_resource("resources"))
    )
  )

  list(
    app = app,
    shutdown = function() {
      monitor_enabled <<- FALSE
      monitor_running <<- FALSE
      rm(list = ls(sockets, all.names = TRUE), envir = sockets)
      invisible(NULL)
    }
  )
}

#' A local source-file streaming server
#'
#' This class is returned by [serve_file()]. Use `$stop()`, `$start()`, or
#' `$restart()` to manage the server.
#'
#' @param path Normalized path to the streamed file.
#' @param host Address on which the server listens.
#' @param port TCP port used by the server.
#' @param interval Browser polling interval in seconds.
#' @param open_browser Whether to open the local viewer.
#'
#' @keywords internal
LiveCodeServer <- R6::R6Class(
  "LiveCodeServer",
  cloneable = FALSE,
  private = list(
    file_path = NULL,
    bind_host = NULL,
    bind_port = NULL,
    interval = NULL,
    server = NULL,
    stream = NULL
  ),
  public = list(
    #' @description Create and start a streaming server.
    initialize = function(path, host, port, interval, open_browser) {
      private$file_path <- normalizePath(path, mustWork = TRUE)
      private$bind_host <- host
      private$bind_port <- port
      private$interval <- interval
      self$start()

      if (isTRUE(open_browser)) {
        utils::browseURL(self$url)
      }
    },

    #' @description Start the server if it is stopped.
    start = function() {
      if (self$is_running()) {
        return(invisible(self))
      }

      private$stream <- make_stream_app(private$file_path, private$interval)
      private$server <- tryCatch(
        httpuv::startServer(
          private$bind_host,
          private$bind_port,
          private$stream$app,
          quiet = TRUE
        ),
        error = function(error) {
          stop(
            sprintf(
              "Could not start livecode at %s:%d: %s",
              private$bind_host,
              private$bind_port,
              conditionMessage(error)
            ),
            call. = FALSE
          )
        }
      )

      register_server(self)
      message(sprintf("Started streaming '%s' at %s", basename(private$file_path), self$url))
      if (identical(private$bind_host, "0.0.0.0")) {
        message(sprintf(
          "For Wi-Fi viewers, replace 127.0.0.1 with this computer's LAN IP and keep port %d.",
          private$bind_port
        ))
      }

      invisible(self)
    },

    #' @description Stop the server immediately.
    stop = function() {
      if (!self$is_running()) {
        return(invisible(self))
      }

      private$server$stop()
      private$stream$shutdown()
      private$server <- NULL
      private$stream <- NULL
      deregister_server(self)
      message(sprintf("Stopped server at %s", self$url))
      invisible(self)
    },

    #' @description Stop and then start the server.
    restart = function() {
      self$stop()
      self$start()
    },

    #' @description Report whether the underlying HTTP server is running.
    is_running = function() {
      !is.null(private$server) && isTRUE(private$server$isRunning())
    },

    #' @description Print the server status, file, and local URL.
    #' @param ... Unused.
    print = function(...) {
      status <- if (self$is_running()) "running" else "stopped"
      cat(sprintf("<livecode server: %s>\n  file: %s\n  url:  %s\n",
                  status, private$file_path, self$url))
      invisible(self)
    }
  ),
  active = list(
    #' @field url Local URL that can be opened on the presenting computer.
    url = function() {
      display_host <- if (identical(private$bind_host, "0.0.0.0")) {
        "127.0.0.1"
      } else {
        private$bind_host
      }
      sprintf("http://%s:%d", display_host, private$bind_port)
    },

    #' @field path Absolute path to the streamed file.
    path = function() private$file_path,
    #' @field host Listening address.
    host = function() private$bind_host,
    #' @field port Listening port.
    port = function() private$bind_port
  )
)

#' Stream a local source file to web browsers
#'
#' Starts a local HTTP server and returns a server object. Browsers receive
#' changed source code over WebSockets, with HTTP polling as an automatic
#' fallback when a persistent connection is unavailable.
#'
#' Use `host = "127.0.0.1"` with a local tunnel such as ngrok. Use
#' `host = "0.0.0.0"` to accept connections from devices on the same Wi-Fi or
#' wired network.
#'
#' @param file Path to the source file to stream.
#' @param host Address on which the server listens. Defaults to localhost.
#' @param port TCP port, from 1 through 65535.
#' @param interval Browser polling interval in seconds.
#' @param open_browser Open the local viewer after starting the server.
#'
#' @return A [LiveCodeServer] object, invisibly.
#' @export
serve_file <- function(file, host = "127.0.0.1", port = 3000L,
                       interval = 0.75, open_browser = interactive()) {
  if (!is.character(file) || length(file) != 1L || !nzchar(file)) {
    stop("`file` must be one non-empty path.", call. = FALSE)
  }
  if (!file.exists(path.expand(file))) {
    stop(sprintf("File does not exist: %s", file), call. = FALSE)
  }
  if (dir.exists(path.expand(file))) {
    stop(sprintf("`file` must not be a directory: %s", file), call. = FALSE)
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

  invisible(LiveCodeServer$new(
    path = path.expand(file),
    host = host,
    port = port,
    interval = interval,
    open_browser = open_browser
  ))
}
