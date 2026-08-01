.livecodeR_state <- new.env(parent = emptyenv())
.livecodeR_state$servers <- list()

register_server <- function(server) {
  already_registered <- vapply(
    .livecodeR_state$servers,
    identical,
    logical(1),
    y = server
  )

  if (!any(already_registered)) {
    .livecodeR_state$servers[[length(.livecodeR_state$servers) + 1L]] <- server
  }

  invisible(server)
}

deregister_server <- function(server) {
  matching <- vapply(
    .livecodeR_state$servers,
    identical,
    logical(1),
    y = server
  )
  .livecodeR_state$servers <- .livecodeR_state$servers[!matching]
  invisible(server)
}

#' List livecodeR servers created in this R session
#'
#' @return A list of server objects.
#' @export
list_servers <- function() {
  .livecodeR_state$servers
}

#' Stop every livecodeR server created in this R session
#'
#' @return Invisibly returns `NULL`.
#' @export
stop_all <- function() {
  servers <- .livecodeR_state$servers
  for (server in servers) {
    if (server$is_running()) {
      server$stop()
    }
  }
  invisible(NULL)
}
