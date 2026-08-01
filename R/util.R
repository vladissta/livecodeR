pkg_resource <- function(...) {
  system.file(..., package = "livecode", mustWork = TRUE)
}

html_escape <- function(value) {
  value <- gsub("&", "&amp;", value, fixed = TRUE)
  value <- gsub("<", "&lt;", value, fixed = TRUE)
  value <- gsub(">", "&gt;", value, fixed = TRUE)
  value <- gsub('"', "&quot;", value, fixed = TRUE)
  value
}

render_template <- function(path, title) {
  template <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"),
                    collapse = "\n")
  gsub("{{title}}", html_escape(title), template, fixed = TRUE)
}

json_response <- function(body, status = 200L) {
  list(
    status = as.integer(status),
    headers = list(
      "Content-Type" = "application/json; charset=UTF-8",
      "Cache-Control" = "no-store, max-age=0"
    ),
    body = jsonlite::toJSON(body, auto_unbox = TRUE, null = "null")
  )
}

text_response <- function(body, status = 200L,
                          content_type = "text/plain; charset=UTF-8") {
  list(
    status = as.integer(status),
    headers = list("Content-Type" = content_type),
    body = body
  )
}

client_revision <- function(query_string) {
  if (is.null(query_string) || !nzchar(query_string)) {
    return(NULL)
  }

  query_string <- sub("?", "", query_string, fixed = TRUE)
  fields <- strsplit(query_string, "&", fixed = TRUE)[[1L]]
  revision_field <- fields[startsWith(fields, "revision=")]
  if (length(revision_field) != 1L) {
    return(NULL)
  }

  value <- substring(revision_field, nchar("revision=") + 1L)
  if (!grepl("^[0-9]+$", value)) NULL else as.integer(value)
}
