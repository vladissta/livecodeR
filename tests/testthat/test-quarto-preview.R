test_that("preview_qmd validates its inputs", {
  file <- tempfile(fileext = ".R")
  writeLines("1 + 1", file)
  on.exit(unlink(file), add = TRUE)

  expect_error(
    preview_qmd(file, open_browser = FALSE),
    "must have a .qmd extension",
    fixed = TRUE
  )
  expect_error(
    preview_qmd("missing.qmd", open_browser = FALSE),
    "File does not exist",
    fixed = TRUE
  )
  expect_error(
    preview_qmd(file, open_browser = FALSE, cache = NA),
    "`cache` must be `TRUE` or `FALSE`.",
    fixed = TRUE
  )
})

test_that("Quarto's reported preview port is detected", {
  expect_equal(
    livecodeR:::quarto_preview_port("Browse at http://localhost:41234/"),
    41234L
  )
  expect_null(
    livecodeR:::quarto_preview_port("Document links to http://localhost:9999/")
  )
})

wait_for_quarto_preview <- function(server, timeout = 30) {
  deadline <- Sys.time() + timeout
  logs <- character()

  repeat {
    logs <- server$logs()
    if (!is.null(livecodeR:::quarto_preview_port(logs))) {
      return(logs)
    }
    if (!server$is_running() || Sys.time() >= deadline) {
      return(logs)
    }
    Sys.sleep(0.1)
  }
}

test_that("Quarto preview is managed as a livecodeR server", {
  skip_on_cran()
  skip_if(Sys.which("quarto") == "", "Quarto CLI is not installed")

  file <- tempfile(fileext = ".qmd")
  writeLines(c("---", "title: Test", "---", "", "Hello"), file)
  on.exit(unlink(file), add = TRUE)

  server <- preview_qmd(
    file,
    host = "127.0.0.1",
    port = 43210L,
    open_browser = FALSE,
    auto_save = FALSE
  )
  on.exit(server$stop(), add = TRUE)

  logs <- wait_for_quarto_preview(server)
  reported_port <- livecodeR:::quarto_preview_port(logs)

  expect_false(
    is.null(reported_port),
    info = paste("Quarto preview did not become ready. Logs:",
                 paste(logs, collapse = "\n"), sep = "\n")
  )
  expect_true(server$is_running())
  expect_equal(server$port, reported_port)
  expect_match(server$url, sprintf(":%d$", reported_port))
  expect_true(any(vapply(list_servers(), identical, logical(1), server)))

  server$stop()
  expect_false(server$is_running())
  expect_false(any(vapply(list_servers(), identical, logical(1), server)))
})
