FileCache <- R6::R6Class(
  "FileCache",
  cloneable = FALSE,
  private = list(
    path = NULL,
    mtime = NULL,
    size = NULL,
    content = NULL,
    revision = 0L,

    file_info = function() {
      if (!file.exists(private$path)) {
        stop(sprintf("The streamed file no longer exists: %s", private$path),
             call. = FALSE)
      }

      info <- file.info(private$path)
      if (isTRUE(info$isdir)) {
        stop(sprintf("The streamed path is a directory: %s", private$path),
             call. = FALSE)
      }

      info
    },

    read_content = function(size) {
      connection <- file(private$path, open = "rb")
      on.exit(close(connection), add = TRUE)
      rawToChar(readBin(connection, what = "raw", n = size))
    },

    refresh = function(force = FALSE) {
      info <- private$file_info()
      changed <- force ||
        !identical(info$mtime, private$mtime) ||
        !identical(info$size, private$size)

      if (changed) {
        private$content <- private$read_content(info$size)
        private$mtime <- info$mtime
        private$size <- info$size
        private$revision <- private$revision + 1L
      }

      invisible(changed)
    }
  ),
  public = list(
    initialize = function(path) {
      private$path <- normalizePath(path, mustWork = TRUE)
      private$refresh(force = TRUE)
    },

    state = function(client_revision = NULL) {
      private$refresh()
      changed <- is.null(client_revision) ||
        !identical(as.integer(client_revision), private$revision)

      state <- list(
        changed = changed,
        revision = private$revision
      )

      if (changed) {
        state$content <- private$content
      }

      state
    }
  )
)

file_cache <- function(path) {
  FileCache$new(path)
}
