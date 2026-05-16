#!/usr/bin/env Rscript

# Canonical JSON -> parquet merger for the analysis-version paper pipeline.
#
# Purpose:
#   Convert the staged ADS outputs from `001-collect-ads-records.ipynb`
#   into the three canonical parquet files consumed downstream:
#     - data/papers.parquet
#     - data/paper_arxiv_classes.parquet
#     - data/paper_metrics_long.parquet
#
# Inputs:
#   code/stage-outputs/001-collect-ads-records/ads_search_all_years_with_abstracts.json
#   code/stage-outputs/001-collect-ads-records/ads_search_all_years_metrics_citations.json
#
# Public repo note:
#   In the public transparency repository, those extracted JSONs are normally
#   recreated by unzipping:
#   code/stage-outputs/001-collect-ads-records/ads_stage_001_snapshots.zip
#
# Optional environment overrides:
#   DM_MERGE_RECORDS_JSON
#   DM_MERGE_METRICS_JSON
#   DM_DATA_OUTPUT_DIR
#   DM_METRIC_TYPES              comma-separated, defaults to "citations"

suppressWarnings(suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(jsonlite)
  library(purrr)
  library(stringr)
  library(tibble)
  library(tidyr)
}))

detect_code_root <- function() {
  cwd <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  if (basename(cwd) == "code") {
    return(cwd)
  }

  candidate <- file.path(cwd, "code")
  if (dir.exists(candidate)) {
    return(normalizePath(candidate, winslash = "/", mustWork = TRUE))
  }

  stop("Run this script from the production root or from code/.", call. = FALSE)
}

code_root <- detect_code_root()
project_root <- normalizePath(file.path(code_root, ".."), winslash = "/", mustWork = TRUE)
output_dir <- Sys.getenv("DM_DATA_OUTPUT_DIR", unset = file.path(project_root, "data"))

default_records_json <- file.path(
  code_root, "stage-outputs", "001-collect-ads-records", "ads_search_all_years_with_abstracts.json"
)
default_metrics_json <- file.path(
  code_root, "stage-outputs", "001-collect-ads-records", "ads_search_all_years_metrics_citations.json"
)
default_snapshot_zip <- file.path(
  code_root, "stage-outputs", "001-collect-ads-records", "ads_stage_001_snapshots.zip"
)

records_json <- Sys.getenv("DM_MERGE_RECORDS_JSON", unset = default_records_json)
metrics_json <- Sys.getenv("DM_MERGE_METRICS_JSON", unset = default_metrics_json)

metric_types_env <- Sys.getenv("DM_METRIC_TYPES", unset = "citations")
metric_types <- metric_types_env |>
  strsplit(",", fixed = TRUE) |>
  purrr::pluck(1) |>
  trimws() |>
  (\(x) x[nzchar(x)])()

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

assert_exists <- function(path, zip_hint = NULL) {
  if (!file.exists(path)) {
    if (!is.null(zip_hint) && file.exists(zip_hint)) {
      stop(
        paste0(
          "Required input not found: ", path, "\n",
          "Extract the retained stage-001 archive first: ", zip_hint
        ),
        call. = FALSE
      )
    }
    stop("Required input not found: ", path, call. = FALSE)
  }
  invisible(path)
}

assert_exists(records_json, zip_hint = default_snapshot_zip)
assert_exists(metrics_json, zip_hint = default_snapshot_zip)

normalize_chr_list <- function(x) {
  if (is.null(x) || length(x) == 0) {
    return(character())
  }

  out <- unlist(x, recursive = TRUE, use.names = FALSE)
  out <- as.character(out)
  out[!is.na(out) & nzchar(out)]
}

scalar_chr <- function(x) {
  vals <- normalize_chr_list(x)
  if (length(vals) == 0) {
    return(NA_character_)
  }
  vals[[1]]
}

scalar_int <- function(x) {
  value <- scalar_chr(x)
  if (is.na(value)) {
    return(NA_integer_)
  }
  suppressWarnings(as.integer(value))
}

build_records_table <- function(records_raw) {
  tibble(
    bibcode = map_chr(records_raw, ~ scalar_chr(.x$bibcode)),
    abstract = map_chr(records_raw, ~ scalar_chr(.x$abstract)),
    year = map_int(records_raw, ~ scalar_int(.x$year)),
    doctype = map_chr(records_raw, ~ scalar_chr(.x$doctype)),
    arxiv_class = map(records_raw, ~ normalize_chr_list(.x$arxiv_class))
  ) |>
    filter(!is.na(bibcode), bibcode != "") |>
    distinct(bibcode, .keep_all = TRUE)
}

flatten_metrics <- function(metrics_raw, metric_types = "citations") {
  metric_names <- setdiff(names(metrics_raw), "skipped bibcodes")

  rows <- map(metric_names, function(bibcode) {
    metrics <- metrics_raw[[bibcode]]
    row <- list(bibcode = bibcode)

    if (!is.list(metrics) || is.null(names(metrics))) {
      return(as_tibble(row))
    }

    metric_keys <- intersect(names(metrics), metric_types)

    for (metric_name in metric_keys) {
      value <- metrics[[metric_name]]
      if (is.list(value) && !is.null(names(value))) {
        for (sub_name in names(value)) {
          row[[paste0(metric_name, "__", sub_name)]] <- value[[sub_name]]
        }
      } else {
        row[[metric_name]] <- value
      }
    }

    as_tibble(row)
  })

  bind_rows(rows)
}

categorize_arxiv <- function(arxiv_class) {
  case_when(
    str_detect(arxiv_class, "^astro") ~ "astrophysics",
    str_detect(arxiv_class, "^hep-") ~ "high-energy physics",
    str_detect(arxiv_class, "^cond-mat") ~ "condensed matter",
    str_detect(arxiv_class, "^math") ~ "mathematics",
    str_detect(arxiv_class, "^cs") ~ "computer science",
    str_detect(arxiv_class, "^quant-ph") ~ "quantum physics",
    str_detect(arxiv_class, "^gr-qc") ~ "general relativity and quantum cosmology",
    str_detect(arxiv_class, "^nucl-") ~ "nuclear physics",
    str_detect(arxiv_class, "^physics") ~ "physics",
    str_detect(arxiv_class, "^q-bio") ~ "quantitative biology",
    str_detect(arxiv_class, "^q-fin") ~ "quantitative finance",
    str_detect(arxiv_class, "^stat") ~ "statistics",
    str_detect(arxiv_class, "^econ") ~ "economics",
    str_detect(arxiv_class, "^eess") ~ "electrical engineering and systems science",
    str_detect(arxiv_class, "^nlin") ~ "nonlinear sciences",
    TRUE ~ "Other"
  )
}

write_output <- function(data, file_name) {
  path <- file.path(output_dir, file_name)
  write_parquet(data, path)
  invisible(path)
}

report_table <- function(label, data) {
  cat(sprintf(" - %s: %s rows\n", label, format(nrow(data), big.mark = ",")))
}

records_raw <- fromJSON(records_json, simplifyVector = FALSE)
metrics_raw <- fromJSON(metrics_json, simplifyVector = FALSE)

papers <- build_records_table(records_raw) |>
  transmute(
    bibcode,
    abstract,
    year = as.integer(year),
    doctype
  )

paper_arxiv_classes <- build_records_table(records_raw) |>
  transmute(
    bibcode,
    arxiv_class = arxiv_class
  ) |>
  unnest_longer(arxiv_class, indices_to = "class_pos") |>
  mutate(arxiv_category = categorize_arxiv(arxiv_class))

citation_history <- flatten_metrics(metrics_raw, metric_types = metric_types) |>
  select(
    bibcode,
    matches("__[0-9]{4}$")
  ) |>
  pivot_longer(
    cols = -bibcode,
    names_to = c("metric", "metric_year"),
    names_pattern = "^(.*)__([0-9]{4})$",
    values_to = "value",
    values_drop_na = TRUE
  ) |>
  mutate(metric_year = as.integer(metric_year))

write_output(papers, "papers.parquet")
write_output(paper_arxiv_classes, "paper_arxiv_classes.parquet")
write_output(citation_history, "paper_metrics_long.parquet")

cat("Wrote canonical merger outputs:\n")
report_table("papers.parquet", papers)
report_table("paper_arxiv_classes.parquet", paper_arxiv_classes)
report_table("paper_metrics_long.parquet", citation_history)

cat("\nInput files:\n")
cat(" - ", records_json, "\n", sep = "")
cat(" - ", metrics_json, "\n", sep = "")

cat("\nOutput directory:\n")
cat(" - ", output_dir, "\n", sep = "")
