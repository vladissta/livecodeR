run_network_command <- function(command, args = character()) {
  if (!nzchar(Sys.which(command))) {
    return(character())
  }

  suppressWarnings(tryCatch(
    system2(command, args, stdout = TRUE, stderr = FALSE),
    error = function(error) character()
  ))
}

extract_ipv4_addresses <- function(lines) {
  if (!length(lines)) {
    return(character())
  }

  matches <- regmatches(
    lines,
    gregexpr("(?<![0-9])(?:[0-9]{1,3}\\.){3}[0-9]{1,3}(?![0-9])",
             lines, perl = TRUE)
  )
  addresses <- unique(unlist(matches, use.names = FALSE))
  if (!length(addresses)) {
    return(character())
  }

  valid <- vapply(strsplit(addresses, ".", fixed = TRUE), function(parts) {
    values <- suppressWarnings(as.integer(parts))
    length(values) == 4L && !anyNA(values) && all(values >= 0L & values <= 255L)
  }, logical(1))
  addresses[valid]
}

usable_ipv4_address <- function(address) {
  parts <- as.integer(strsplit(address, ".", fixed = TRUE)[[1L]])
  !(parts[[1L]] %in% c(0L, 127L)) &&
    !(parts[[1L]] == 169L && parts[[2L]] == 254L) &&
    parts[[1L]] < 224L
}

private_ipv4_address <- function(address) {
  parts <- as.integer(strsplit(address, ".", fixed = TRUE)[[1L]])
  parts[[1L]] == 10L ||
    (parts[[1L]] == 172L && parts[[2L]] >= 16L && parts[[2L]] <= 31L) ||
    (parts[[1L]] == 192L && parts[[2L]] == 168L)
}

order_ipv4_addresses <- function(addresses) {
  addresses <- unique(addresses[vapply(
    addresses,
    usable_ipv4_address,
    logical(1)
  )])
  if (!length(addresses)) {
    return(character())
  }

  private <- vapply(addresses, private_ipv4_address, logical(1))
  c(addresses[private], addresses[!private])
}

network_ipv4_candidates <- function(
    system_name = Sys.info()[["sysname"]],
    run = run_network_command) {
  addresses <- character()
  preferred <- character()

  if (identical(system_name, "Darwin")) {
    route <- run("route", c("-n", "get", "default"))
    interface_lines <- route[grepl("^[[:space:]]*interface:", route)]
    if (length(interface_lines)) {
      interface <- trimws(sub("^[^:]+:", "", interface_lines[[1L]]))
      preferred <- extract_ipv4_addresses(
        run("ipconfig", c("getifaddr", interface))
      )
      addresses <- c(addresses, preferred)
    }
  } else if (identical(system_name, "Linux")) {
    route <- run("ip", c("route", "get", "1.1.1.1"))
    source_lines <- route[grepl("(?:^|[[:space:]])src[[:space:]]", route)]
    if (length(source_lines)) {
      source <- sub(
        ".*(?:^|[[:space:]])src[[:space:]]+([0-9.]+).*",
        "\\1",
        source_lines,
        perl = TRUE
      )
      preferred <- extract_ipv4_addresses(source)
      addresses <- c(addresses, preferred)
    }
  } else if (identical(system_name, "Windows")) {
    route <- run("route", c("print", "-4"))
    default_routes <- route[grepl(
      "^[[:space:]]*0\\.0\\.0\\.0[[:space:]]+0\\.0\\.0\\.0[[:space:]]+",
      route
    )]
    if (length(default_routes)) {
      fields <- strsplit(trimws(default_routes[[1L]]), "[[:space:]]+")[[1L]]
      if (length(fields) >= 4L) {
        preferred <- extract_ipv4_addresses(fields[[4L]])
        addresses <- c(addresses, preferred)
      }
    }

    config <- run("ipconfig")
    ipv4_lines <- config[grepl("IPv4[^:]*:", config, ignore.case = TRUE)]
    addresses <- c(addresses, extract_ipv4_addresses(ipv4_lines))
  }

  if (!identical(system_name, "Windows")) {
    addresses <- c(addresses, extract_ipv4_addresses(
      run("hostname", "-I")
    ))

    config <- run("ifconfig")
    inet_lines <- config[grepl(
      "^[[:space:]]*inet(?:[[:space:]]| addr:)",
      config
    )]
    if (length(inet_lines)) {
      inet_values <- sub(
        "^[[:space:]]*inet(?:[[:space:]]+addr:)?[[:space:]]*([0-9.]+).*",
        "\\1",
        inet_lines
      )
      addresses <- c(addresses, extract_ipv4_addresses(inet_values))
    }
  }

  preferred <- order_ipv4_addresses(preferred)
  ordered <- order_ipv4_addresses(addresses)
  c(preferred, setdiff(ordered, preferred))
}

local_ipv4_addresses <- function() {
  addresses <- network_ipv4_candidates()
  if (length(addresses)) {
    return(addresses)
  }

  hostname <- Sys.info()[["nodename"]]
  if (is.null(hostname) || is.na(hostname) || !nzchar(hostname)) {
    return(character())
  }

  resolved <- suppressWarnings(tryCatch(
    utils::nsl(hostname),
    error = function(error) NULL
  ))
  order_ipv4_addresses(extract_ipv4_addresses(resolved))
}

#' Find this computer's local-network IP address
#'
#' Finds the preferred IPv4 address that another device on the same local
#' network can use to reach this computer. This is useful with
#' `serve_file(host = "0.0.0.0")`, because `0.0.0.0` is a listening address
#' rather than an address that can be opened in a browser.
#'
#' @return A single IPv4 address. Returns `NA` with a warning when an address
#'   cannot be detected, for example when the computer is offline.
#' @export
local_ip <- function() {
  addresses <- local_ipv4_addresses()
  if (!length(addresses)) {
    warning(
      "Could not determine this computer's local-network IPv4 address.",
      call. = FALSE
    )
    return(NA_character_)
  }
  addresses[[1L]]
}
