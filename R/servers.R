.livecode_state <- new.env(parent = emptyenv())
.livecode_state$servers <- list()

register_server <- function(server) {
  already_registered <- vapply(
    .livecode_state$servers,
    identical,
    logical(1),
    y = server
  )

  if (!any(already_registered)) {
    .livecode_state$servers[[length(.livecode_state$servers) + 1L]] <- server
  }

  invisible(server)
}

deregister_server <- function(server) {
  matching <- vapply(
    .livecode_state$servers,
    identical,
    logical(1),
    y = server
  )
  .livecode_state$servers <- .livecode_state$servers[!matching]
  invisible(server)
}

#' List livecode servers created in this R session
#'
#' @return A list of server objects.
#' @export
list_servers <- function() {
  .livecode_state$servers
}

#' Stop every livecode server created in this R session
#'
#' @return Invisibly returns `NULL`.
#' @export
stop_all <- function() {
  servers <- .livecode_state$servers
  for (server in servers) {
    if (server$is_running()) {
      server$stop()
    }
  }
  invisible(NULL)
}
