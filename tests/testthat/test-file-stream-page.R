test_that("stream page versions livecode assets from their contents", {
  file <- tempfile(fileext = ".R")
  writeLines("answer <- 42", file)
  withr::defer(unlink(file))

  stream <- livecodeR:::make_stream_app(file, interval = 0.75)
  withr::defer(stream$shutdown())
  response <- stream$app$call(list(PATH_INFO = "/"))

  expect_equal(response$status, 200L)
  expect_match(
    response$body,
    "/web/livecode/livecode\\.css\\?v=[[:xdigit:]]{64}"
  )
  expect_match(
    response$body,
    "/web/livecode/livecode\\.js\\?v=[[:xdigit:]]{64}"
  )
})
