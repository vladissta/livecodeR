test_that("IPv4 addresses are extracted and validated", {
  expect_equal(
    livecodeR:::extract_ipv4_addresses(c(
      "inet 192.168.1.42 netmask 0xffffff00",
      "invalid 999.1.2.3 and 10.0.0.8"
    )),
    c("192.168.1.42", "10.0.0.8")
  )
})

test_that("private LAN addresses are preferred", {
  expect_equal(
    livecodeR:::order_ipv4_addresses(c(
      "127.0.0.1",
      "203.0.113.7",
      "192.168.1.42",
      "169.254.2.3"
    )),
    c("192.168.1.42", "203.0.113.7")
  )
})

test_that("the default macOS interface is used", {
  run <- function(command, args = character()) {
    key <- paste(c(command, args), collapse = " ")
    switch(
      key,
      "route -n get default" = "  interface: en7",
      "ipconfig getifaddr en7" = "192.168.20.14",
      character()
    )
  }

  expect_equal(
    livecodeR:::network_ipv4_candidates("Darwin", run),
    "192.168.20.14"
  )
})

test_that("the Linux route source address is used", {
  run <- function(command, args = character()) {
    key <- paste(c(command, args), collapse = " ")
    switch(
      key,
      "ip route get 1.1.1.1" =
        "1.1.1.1 via 10.0.0.1 dev wlan0 src 10.0.0.24 uid 1000",
      character()
    )
  }

  expect_equal(
    livecodeR:::network_ipv4_candidates("Linux", run),
    "10.0.0.24"
  )
})

test_that("a default-route address is preferred over fallback interfaces", {
  run <- function(command, args = character()) {
    key <- paste(c(command, args), collapse = " ")
    switch(
      key,
      "ip route get 1.1.1.1" =
        "1.1.1.1 via 203.0.113.1 dev eth0 src 203.0.113.20 uid 1000",
      "hostname -I" = "192.168.122.1 203.0.113.20",
      character()
    )
  }

  expect_equal(
    livecodeR:::network_ipv4_candidates("Linux", run),
    c("203.0.113.20", "192.168.122.1")
  )
})

test_that("the Windows default route interface is used", {
  run <- function(command, args = character()) {
    key <- paste(c(command, args), collapse = " ")
    switch(
      key,
      "route print -4" = paste(
        "Network Destination        Netmask          Gateway       Interface  Metric",
        "          0.0.0.0          0.0.0.0     192.168.1.1    192.168.1.42     25",
        sep = "\n"
      ),
      "ipconfig" = "   IPv4 Address. . . . . . . . . . . : 192.168.1.42",
      character()
    )
  }

  expect_equal(
    livecodeR:::network_ipv4_candidates("Windows", run),
    "192.168.1.42"
  )
})

test_that("serve_file reports and retains its LAN URL", {
  running <- TRUE
  fake_server <- list(
    isRunning = function() running,
    stop = function() running <<- FALSE
  )
  local_mocked_bindings(
    local_ipv4_addresses = function() "192.168.50.12",
    .package = "livecodeR"
  )
  local_mocked_bindings(
    startServer = function(...) fake_server,
    .package = "httpuv"
  )

  file <- tempfile(fileext = ".R")
  writeLines("1 + 1", file)
  on.exit(unlink(file), add = TRUE)

  expect_message(
    server <- serve_file(
      file,
      host = "0.0.0.0",
      port = 3000L,
      open_browser = FALSE,
      auto_save = FALSE
    ),
    "Network URL: http://192.168.50.12:3000",
    fixed = TRUE
  )
  on.exit(server$stop(), add = TRUE)

  expect_equal(server$lan_url, "http://192.168.50.12:3000")
  expect_match(
    paste(capture.output(print(server)), collapse = "\n"),
    "lan:  http://192.168.50.12:3000",
    fixed = TRUE
  )
})
