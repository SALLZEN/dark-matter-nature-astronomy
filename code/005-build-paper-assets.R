#!/usr/bin/env Rscript

# Canonical manuscript-asset reproduction script for the analysis-version repo.
#
# Canonical inputs:
#   data/papers.parquet
#   data/paper_arxiv_classes.parquet
#   data/paper_metrics_long.parquet
#   data/dm_model_candidates_long.parquet
#   data/unigram_yearly.parquet
#
# Canonical outputs:
#   figures/fig_composition_batlow.pdf
#   figures/fig_candidate_raw_vs_norm_batlow.pdf
#   figures/fig_candidate_field_log_ratio.pdf
#   figures/fig_uni_grams_trends.pdf
#   tables/table_model_terms.tex
#
# This script is intentionally staged for human inspection:
#   1. Load the canonical parquet inputs
#   2. Validate the required columns
#   3. Prepare the composition inputs
#   4. Prepare the candidate inputs
#   5. Render the manuscript figures and table

suppressWarnings(suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(readr)
  library(purrr)
  library(ggplot2)
  library(patchwork)
  library(scales)
  library(khroma)
  library(viridisLite)
  library(ggalt)
  library(grid)
}))

options(lifecycle_verbosity = "quiet")

BASE_FONT <- "Helvetica"

detect_script_dir <- function() {
  decode_arg_path <- function(path) {
    path <- gsub("~\\+~", " ", path)
    gsub("\\\\ ", " ", path)
  }

  cmd_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- "--file="
  file_match <- grep(paste0("^", file_arg), cmd_args, value = TRUE)
  if (length(file_match) > 0) {
    script_path <- decode_arg_path(sub(file_arg, "", file_match[[1]]))
    return(dirname(normalizePath(script_path, winslash = "/", mustWork = TRUE)))
  }

  if (!is.null(sys.frames()[[1]]$ofile)) {
    script_path <- decode_arg_path(sys.frames()[[1]]$ofile)
    return(dirname(normalizePath(script_path, winslash = "/", mustWork = TRUE)))
  }

  NULL
}

detect_root_dir <- function() {
  candidates <- character()

  script_dir <- detect_script_dir()
  if (!is.null(script_dir)) {
    candidates <- c(
      candidates,
      script_dir,
      normalizePath(file.path(script_dir, ".."), winslash = "/", mustWork = FALSE)
    )
  }

  cwd <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  candidates <- c(
    candidates,
    cwd,
    normalizePath(file.path(cwd, ".."), winslash = "/", mustWork = FALSE)
  )

  candidates <- unique(candidates[dir.exists(candidates)])
  for (candidate in candidates) {
    if (dir.exists(file.path(candidate, "data")) && dir.exists(file.path(candidate, "figures"))) {
      return(normalizePath(candidate, winslash = "/", mustWork = TRUE))
    }
  }

  stop("Could not locate the production root. Run from the production root or keep this script inside it.", call. = FALSE)
}

ROOT_DIR <- detect_root_dir()
DATA_DIR <- file.path(ROOT_DIR, "data")
FIG_DIR <- file.path(ROOT_DIR, "figures")
TABLE_DIR <- file.path(ROOT_DIR, "tables")

resolve_input <- function(env_var, default_name) {
  path <- Sys.getenv(env_var, unset = file.path(DATA_DIR, default_name))
  if (!file.exists(path)) {
    stop(sprintf("Missing required input file: %s", path), call. = FALSE)
  }
  path
}

ensure_output_dirs <- function() {
  dir.create(FIG_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(TABLE_DIR, recursive = TRUE, showWarnings = FALSE)
}

print_stage <- function(title) {
  message("\n== ", title, " ==")
}

report_input_inventory <- function(inputs) {
  message("Loaded canonical inputs:")
  message("  papers: ", nrow(inputs$papers), " rows")
  message("  paper_arxiv_classes: ", nrow(inputs$paper_arxiv_classes), " rows")
  message("  paper_metrics_long: ", nrow(inputs$metrics), " rows")
  message("  dm_model_candidates_long: ", nrow(inputs$dm_candidates), " rows")
  message("  unigram_yearly: ", nrow(inputs$unigram_yearly), " rows")
}

assert_has_columns <- function(data, required, label) {
  missing <- setdiff(required, names(data))
  if (length(missing) > 0) {
    stop(
      sprintf(
        "%s is missing required columns: %s",
        label,
        paste(missing, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

validate_inputs <- function(inputs) {
  assert_has_columns(inputs$papers, c("bibcode", "abstract", "year", "doctype"), "papers.parquet")
  assert_has_columns(
    inputs$paper_arxiv_classes,
    c("bibcode", "arxiv_class", "class_pos", "arxiv_category"),
    "paper_arxiv_classes.parquet"
  )
  assert_has_columns(inputs$metrics, c("bibcode", "metric", "metric_year", "value"), "paper_metrics_long.parquet")
  assert_has_columns(
    inputs$dm_candidates,
    c("bibcode", "year", "arxiv_category", "tag", "SpeciesLabel"),
    "dm_model_candidates_long.parquet"
  )
  assert_has_columns(inputs$unigram_yearly, c("year", "field", "term", "n_kw", "n_papers", "rate"), "unigram_yearly.parquet")
  invisible(inputs)
}

load_inputs <- function() {
  list(
    papers = read_parquet(resolve_input("NATURE_PAPERS_PATH", "papers.parquet")),
    paper_arxiv_classes = read_parquet(resolve_input("NATURE_ARXIV_CLASSES_PATH", "paper_arxiv_classes.parquet")),
    metrics = read_parquet(resolve_input("NATURE_METRICS_PATH", "paper_metrics_long.parquet")),
    dm_candidates = read_parquet(resolve_input("NATURE_DM_CANDIDATES_PATH", "dm_model_candidates_long.parquet")),
    unigram_yearly = read_parquet(resolve_input("NATURE_UNIGRAM_PATH", "unigram_yearly.parquet"), show_col_types = FALSE)
  )
}

prepare_papers <- function(papers, paper_arxiv_classes) {
  names(papers) <- trimws(names(papers))
  names(paper_arxiv_classes) <- trimws(names(paper_arxiv_classes))

  primary_classes <- paper_arxiv_classes |>
    filter(class_pos == 1) |>
    select(bibcode, arxiv_class, arxiv_category)

  papers |>
    select(-any_of(c("arxiv_class", "arxiv_category"))) |>
    left_join(primary_classes, by = "bibcode")
}

prepare_candidate_long <- function(candidate_long, papers) {
  papers_lookup <- papers |>
    select(bibcode, paper_year = year, paper_arxiv_category = arxiv_category)

  candidate_long |>
    left_join(papers_lookup, by = "bibcode") |>
    mutate(
      year = dplyr::coalesce(year, paper_year),
      arxiv_category = dplyr::case_when(
        is.na(arxiv_category) ~ paper_arxiv_category,
        arxiv_category %in% c("", "Other") ~ paper_arxiv_category,
        TRUE ~ arxiv_category
      )
    ) |>
    select(-paper_year, -paper_arxiv_category)
}

report_prepared_data <- function(papers, candidate_long, unigram_yearly) {
  primary_classes <- papers |>
    count(arxiv_category, sort = TRUE)

  message("Prepared paper-level data:")
  message("  papers with primary arXiv category: ", sum(!is.na(papers$arxiv_category)))
  message("  distinct paper years: ", dplyr::n_distinct(papers$year, na.rm = TRUE))
  message("  primary categories:")
  for (i in seq_len(nrow(primary_classes))) {
    message("    - ", primary_classes$arxiv_category[[i]], ": ", primary_classes$n[[i]])
  }

  message("Prepared candidate-level data:")
  message("  candidate rows: ", nrow(candidate_long))
  message("  unique candidate labels: ", dplyr::n_distinct(candidate_long$SpeciesLabel, na.rm = TRUE))

  message("Prepared lexical data:")
  message("  unigram rows: ", nrow(unigram_yearly))
  message("  fields: ", paste(sort(unique(unigram_yearly$field)), collapse = ", "))
}

theme_nature <- function(base_size = 7) {
  theme_light(base_size = base_size, base_family = BASE_FONT) +
    theme(
      panel.grid = element_blank(),
      panel.background = element_rect(fill = "white", color = NA),
      plot.background = element_rect(fill = "white", color = NA),
      text = element_text(family = BASE_FONT, color = "black", size = base_size),
      axis.text = element_text(color = "black", size = base_size - 1),
      axis.title = element_text(color = "black", size = base_size),
      axis.ticks = element_line(color = "black", linewidth = 0.3),
      legend.text = element_text(color = "black", size = base_size - 1),
      legend.title = element_text(color = "black", size = base_size),
      legend.key = element_rect(fill = NA, color = NA),
      legend.margin = margin(2, 2, 2, 2),
      plot.title = element_text(color = "black", size = base_size, hjust = 0.5),
      plot.subtitle = element_text(color = "black", size = base_size - 1, hjust = 0.5),
      plot.tag = element_text(color = "black", size = 7)
    )
}

save_pdf <- function(plot, file, width_mm, height_mm) {
  path <- file.path(FIG_DIR, file)
  if (capabilities("aqua")) {
    grDevices::quartz(
      file = path,
      type = "pdf",
      width = width_mm / 25.4,
      height = height_mm / 25.4,
      family = BASE_FONT
    )
  } else {
    grDevices::pdf(
      file = path,
      width = width_mm / 25.4,
      height = height_mm / 25.4,
      family = BASE_FONT,
      useDingbats = FALSE
    )
  }
  on.exit(grDevices::dev.off(), add = TRUE)
  print(plot)
  invisible(path)
}

prepare_candidate_trends <- function(candidate_long) {
  trend <- candidate_long |>
    filter(
      !is.na(SpeciesLabel),
      SpeciesLabel != "",
      SpeciesLabel != "Other/Uncategorized"
    )

  top_models <- trend |>
    filter(arxiv_category == "high-energy physics", year >= 1995) |>
    distinct(bibcode, SpeciesLabel) |>
    count(SpeciesLabel, name = "total") |>
    slice_max(total, n = 9, with_ties = FALSE) |>
    pull(SpeciesLabel)

  astro_top_models <- trend |>
    filter(arxiv_category == "astrophysics", year >= 1995) |>
    distinct(bibcode, SpeciesLabel) |>
    count(SpeciesLabel, name = "total") |>
    slice_max(total, n = 9, with_ties = FALSE) |>
    pull(SpeciesLabel)

  species <- union(top_models, astro_top_models) |> sort()
  cols <- khroma::color("batlow", type = "qualitative", reverse = TRUE)(length(species))
  col_map <- setNames(as.character(cols), species)

  dm_model_trends <- trend |>
    filter(
      arxiv_category == "high-energy physics",
      year >= 1995,
      !is.na(SpeciesLabel),
      SpeciesLabel != "Other/Uncategorized",
      SpeciesLabel %in% top_models
    ) |>
    distinct(year, bibcode, SpeciesLabel) |>
    count(year, SpeciesLabel, name = "n")

  astro_dm_model_trends <- trend |>
    filter(
      arxiv_category == "astrophysics",
      year >= 1995,
      !is.na(SpeciesLabel),
      SpeciesLabel != "Other/Uncategorized",
      SpeciesLabel %in% astro_top_models
    ) |>
    distinct(year, bibcode, SpeciesLabel) |>
    count(year, SpeciesLabel, name = "n")

  dm_model_trends_candidate_share <- trend |>
    filter(
      arxiv_category == "high-energy physics",
      year >= 1995,
      !is.na(SpeciesLabel),
      SpeciesLabel != "Other/Uncategorized",
      SpeciesLabel %in% top_models
    ) |>
    distinct(year, arxiv_category, bibcode, SpeciesLabel) |>
    count(year, arxiv_category, SpeciesLabel, name = "n") |>
    group_by(year, arxiv_category) |>
    mutate(share_tracked_candidates = n / sum(n)) |>
    ungroup()

  astro_dm_model_trends_candidate_share <- trend |>
    filter(
      arxiv_category == "astrophysics",
      year >= 1995,
      !is.na(SpeciesLabel),
      SpeciesLabel != "Other/Uncategorized",
      SpeciesLabel %in% astro_top_models
    ) |>
    distinct(year, arxiv_category, bibcode, SpeciesLabel) |>
    count(year, arxiv_category, SpeciesLabel, name = "n") |>
    group_by(year, arxiv_category) |>
    mutate(share_tracked_candidates = n / sum(n)) |>
    ungroup()

  list(
    trend = trend,
    species = species,
    col_map = col_map,
    dm_model_trends = dm_model_trends,
    astro_dm_model_trends = astro_dm_model_trends,
    dm_model_trends_candidate_share = dm_model_trends_candidate_share,
    astro_dm_model_trends_candidate_share = astro_dm_model_trends_candidate_share
  )
}

write_candidate_table <- function(trend, species) {
  candidate_totals <- trend |>
    filter(
      year >= 1995,
      arxiv_category %in% c("astrophysics", "high-energy physics"),
      !is.na(SpeciesLabel),
      SpeciesLabel != "Other/Uncategorized",
      SpeciesLabel %in% species
    ) |>
    distinct(arxiv_category, bibcode, SpeciesLabel) |>
    count(arxiv_category, SpeciesLabel, name = "mentions") |>
    arrange(arxiv_category, desc(mentions))

  path <- file.path(TABLE_DIR, "table_model_terms.tex")
  astro <- candidate_totals |> filter(arxiv_category == "astrophysics")
  hep <- candidate_totals |> filter(arxiv_category == "high-energy physics")

  latex_label <- function(x) {
    dplyr::case_when(
      x == "Sterile ν" ~ "Sterile $\\nu$",
      TRUE ~ x
    )
  }

  max_rows <- max(nrow(astro), nrow(hep))
  astro_rows <- tibble::tibble(
    astro_term = rep("", max_rows),
    astro_mentions = rep("", max_rows)
  )
  hep_rows <- tibble::tibble(
    hep_term = rep("", max_rows),
    hep_mentions = rep("", max_rows)
  )

  if (nrow(astro) > 0) {
    astro_rows$astro_term[seq_len(nrow(astro))] <- vapply(astro$SpeciesLabel, latex_label, character(1))
    astro_rows$astro_mentions[seq_len(nrow(astro))] <- formatC(astro$mentions, format = "d", big.mark = ",")
  }

  if (nrow(hep) > 0) {
    hep_rows$hep_term[seq_len(nrow(hep))] <- vapply(hep$SpeciesLabel, latex_label, character(1))
    hep_rows$hep_mentions[seq_len(nrow(hep))] <- formatC(hep$mentions, format = "d", big.mark = ",")
  }

  table_rows <- dplyr::bind_cols(astro_rows, hep_rows)

  con <- file(path, "w")
  on.exit(close(con), add = TRUE)

  cat("\\begingroup\\fontsize{8}{10}\\selectfont\n", file = con)
  cat(
    "\\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}>{\\raggedright\\arraybackslash}p{0.29\\textwidth}r>{\\raggedright\\arraybackslash}p{0.29\\textwidth}r@{}}\n",
    file = con
  )
  cat("\\toprule\n", file = con)
  cat("\\multicolumn{2}{c}{\\textbf{Astrophysics}} & \\multicolumn{2}{c}{\\textbf{High-energy physics}}\\\\\n", file = con)
  cat("\\cmidrule(r){1-2}\\cmidrule(l){3-4}\n", file = con)
  cat("Term & Mentions & Term & Mentions\\\\\n", file = con)
  cat("\\midrule\n", file = con)
  for (i in seq_len(nrow(table_rows))) {
    cat(
      sprintf(
        "%s & %s & %s & %s\\\\\n",
        table_rows$astro_term[i],
        table_rows$astro_mentions[i],
        table_rows$hep_term[i],
        table_rows$hep_mentions[i]
      ),
      file = con
    )
  }
  cat("\\bottomrule\n", file = con)
  cat("\\end{tabular*}\n", file = con)
  cat("\\endgroup{}\n", file = con)
}

plot_composition <- function(papers, metrics) {
  exclude_more <- c(
    "economics", "mathematics", "quantitative biology",
    "quantitative finance", "statistics", "computer science",
    "electrical engineering and systems science",
    "nuclear physics", "nonlinear sciences"
  )

  paper_year_score <- papers |>
    filter(!arxiv_category %in% exclude_more, !is.na(arxiv_class), year >= 2010) |>
    group_by(arxiv_class, year) |>
    summarise(n_papers = n_distinct(bibcode), .groups = "drop") |>
    filter(n_papers > 20)

  shared_categories <- paper_year_score |>
    group_by(arxiv_class) |>
    summarise(total = sum(n_papers), .groups = "drop") |>
    arrange(desc(total)) |>
    pull(arxiv_class) |>
    head(7)

  pal <- scales::gradient_n_pal(khroma::color("batlow", reverse = TRUE)(256))
  shared_cols <- pal(seq(0, 1, length.out = length(shared_categories)))
  shared_col_map <- setNames(shared_cols, shared_categories)

  color_scale_shared <- scale_color_manual(
    values = shared_col_map,
    breaks = shared_categories,
    limits = shared_categories,
    name = "arXiv class",
    drop = FALSE,
    na.translate = FALSE,
    guide = guide_legend(
      override.aes = list(alpha = 1.0),
      nrow = 1,
      byrow = TRUE,
      keywidth = grid::unit(12, "pt"),
      keyheight = grid::unit(6, "pt")
    )
  )

  theme_panel <- theme_nature()

  dm_genres <- paper_year_score |>
    filter(year >= 2010, year <= 2022, arxiv_class %in% shared_categories) |>
    group_by(year, arxiv_class) |>
    summarise(n_papers = sum(n_papers), .groups = "drop") |>
    group_by(year) |>
    mutate(
      arxiv_class = as.character(arxiv_class),
      prop = n_papers / sum(n_papers)
    ) |>
    ungroup()

  paper_cites_3y <- metrics |>
    filter(metric == "citations") |>
    inner_join(papers |> select(bibcode, pub_year = year), by = "bibcode") |>
    filter(metric_year - pub_year <= 3) |>
    group_by(bibcode) |>
    summarise(cites_3y = sum(value, na.rm = TRUE), .groups = "drop")

  cpp_df <- papers |>
    filter(arxiv_class %in% shared_categories, year >= 2010, year <= 2022) |>
    distinct(bibcode, arxiv_class, year) |>
    left_join(paper_cites_3y, by = "bibcode") |>
    mutate(total_cites = replace_na(cites_3y, 0)) |>
    group_by(year, arxiv_class) |>
    summarise(
      n_papers = n_distinct(bibcode),
      total_cites = sum(total_cites),
      cites_per_paper = total_cites / n_papers,
      .groups = "drop"
    )

  cpp_rank <- cpp_df |>
    group_by(year) |>
    mutate(rank = rank(-cites_per_paper, ties.method = "first")) |>
    ungroup()

  paper_plot <- ggplot(dm_genres, aes(x = year, y = n_papers, color = arxiv_class)) +
    ggalt::geom_xspline(size = 0.3, alpha = 0.9, spline_shape = -0.4) +
    geom_point(size = 0.6, alpha = 0.9) +
    scale_x_continuous(
      breaks = seq(2010, 2022, by = 2),
      expand = expansion(mult = c(0.02, 0.02))
    ) +
    scale_y_continuous(
      trans = "sqrt",
      breaks = c(100, 500, 1000, 2000, 3000),
      labels = scales::label_number(scale_cut = scales::cut_short_scale()),
      expand = expansion(mult = c(0.05, 0.05))
    ) +
    color_scale_shared +
    guides(color = guide_legend(
      nrow = 1,
      byrow = TRUE,
      title = NULL,
      label.position = "bottom",
      override.aes = list(linetype = 0, shape = 19, size = 3)
    )) +
    labs(x = NULL, y = "Papers / year (sqrt)", color = "arXiv class") +
    theme_panel +
    theme(
      axis.ticks.x = element_blank(),
      axis.text.x = element_blank(),
      axis.title.x = element_blank(),
      legend.frame = element_rect(fill = NA, color = "gray65"),
      legend.text = element_text(margin = margin(b = 0, t = -2)),
      axis.title.y = element_text(size = 6),
      axis.text.y = element_text(size = 5)
    )

  impact_lines <- ggplot(cpp_df, aes(year, cites_per_paper, colour = arxiv_class)) +
    ggalt::geom_xspline(size = 0.5, alpha = 0.9, spline_shape = -0.4) +
    geom_point(size = 0.6, alpha = 0.9) +
    scale_x_continuous(
      breaks = seq(2010, 2022, by = 2),
      expand = expansion(mult = c(0.02, 0.02))
    ) +
    scale_y_continuous(
      labels = scales::label_comma(accuracy = 1),
      breaks = scales::breaks_pretty(n = 5),
      expand = expansion(mult = c(0.02, 0.02))
    ) +
    color_scale_shared +
    guides(colour = "none") +
    labs(x = NULL, y = "Citations per paper") +
    theme_panel +
    theme(
      legend.position = "none",
      axis.text.y = element_text(size = 5),
      axis.title.y = element_text(size = 6)
    )

  rank1 <- cpp_rank |>
    mutate(
      year = as.integer(year),
      rank = as.integer(rank)
    ) |>
    filter(rank == 1) |>
    arrange(year)

  impact_strip <- ggplot(rank1, aes(x = year, y = "Rank 1", fill = arxiv_class)) +
    geom_tile(color = "white", linewidth = 0.3) +
    geom_text(
      aes(
        label = scales::number(cites_per_paper, accuracy = 0.1),
        color = if_else(arxiv_class == "hep-ex", "white", "black")
      ),
      size = 2.5
    ) +
    scale_fill_manual(values = shared_col_map) +
    scale_color_identity() +
    labs(
      title = NULL,
      subtitle = NULL,
      x = NULL,
      y = "1",
      fill = NULL
    ) +
    scale_x_continuous(
      breaks = seq(2010, 2022, by = 2),
      expand = expansion(mult = c(-0.02, -0.02))
    ) +
    coord_cartesian(clip = "off") +
    theme_nature() +
    theme(
      panel.grid = element_blank(),
      panel.border = element_blank(),
      axis.text.x = element_text(),
      axis.text.y = element_blank(),
      axis.title.y = element_text(angle = 0, hjust = 0.5, vjust = 0.5),
      axis.ticks.y = element_blank(),
      legend.position = "none"
    )

  genre_winner <- dm_genres |>
    group_by(year) |>
    slice_max(order_by = prop, n = 1, with_ties = FALSE) |>
    ungroup() |>
    mutate(
      text_col = if_else(arxiv_class == "hep-ex", "white", "black")
    )

  papers_strip <- ggplot(genre_winner, aes(x = year, y = "Top share", fill = arxiv_class)) +
    geom_tile(color = "white", linewidth = 0.3) +
    geom_text(
      aes(
        label = scales::percent(prop, accuracy = 0.1),
        color = text_col
      ),
      size = 2.0,
      lineheight = 0.9
    ) +
    scale_x_continuous(
      breaks = seq(2010, 2022, by = 2),
      expand = expansion(mult = c(-0.02, -0.02))
    ) +
    coord_cartesian(clip = "off") +
    scale_fill_manual(values = shared_col_map) +
    scale_color_identity() +
    labs(
      title = NULL,
      subtitle = NULL,
      x = NULL,
      y = "1",
      fill = NULL
    ) +
    theme_nature() +
    theme(
      panel.grid = element_blank(),
      panel.border = element_blank(),
      axis.title.y = element_text(angle = 0, hjust = 0.5, vjust = 0.5),
      axis.text.x = element_text(size = 5),
      axis.text.y = element_blank(),
      axis.ticks.y = element_blank(),
      legend.position = "none"
    )

  paper_plot_wide <- paper_plot +
    guides(color = guide_legend(
      nrow = 1,
      byrow = TRUE,
      title = NULL,
      label.position = "right",
      override.aes = list(linetype = 0, shape = 19, size = 2.5),
      keywidth = grid::unit(10, "pt"),
      keyheight = grid::unit(6, "pt")
    )) +
    labs(y = "Papers/year (sqrt)") +
    theme(
      legend.frame = element_rect(fill = NA, color = "gray85"),
      legend.text = element_text(size = 5.2, margin = margin(l = 1)),
      axis.title.y = element_text(size = 6),
      axis.text.x = element_blank(),
      axis.ticks.x = element_blank(),
      axis.title.x = element_blank()
    )

  impact_lines_wide <- impact_lines +
    labs(y = "Citations/paper") +
    theme(
      axis.text.x = element_blank(),
      axis.ticks.x = element_blank(),
      axis.title.x = element_blank()
    )

  composition_plot_wide_guide <- paper_plot_wide + impact_lines_wide + papers_strip + impact_strip + guide_area() +
    plot_layout(
      design = "
      AABB
      CCDD
      EEEE
      ",
      widths = c(1, 1, 1, 1),
      heights = c(8, 1.15, 0.7),
      guides = "collect",
      axes = "collect"
    ) +
    plot_annotation(tag_levels = list(c("a", "b", "c", ""))) &
    theme(
      plot.tag = element_text(size = 7, family = BASE_FONT),
      plot.tag.position = c(0.01, 0.98),
      axis.text = element_text(size = 5),
      legend.background = element_rect(fill = NA, color = NA),
      legend.frame = element_rect(fill = NA, color = "gray85"),
      legend.margin = margin(0, 0, 0, 0),
      legend.box.margin = margin(0, 0, 0, 0),
      legend.key.spacing.x = grid::unit(5, "pt"),
      legend.key.spacing.y = grid::unit(2, "pt"),
      legend.text = element_text(size = 5.5, margin = margin(r = 0)),
      axis.title.x = element_blank()
    )

  save_pdf(composition_plot_wide_guide, "fig_composition_batlow.pdf", 180, 76)
}

plot_candidate_assets <- function(candidate_data) {
  trend <- candidate_data$trend
  species <- candidate_data$species
  col_map <- candidate_data$col_map
  astro_dm_model_trends <- candidate_data$astro_dm_model_trends
  dm_model_trends <- candidate_data$dm_model_trends
  astro_dm_model_trends_candidate_share <- candidate_data$astro_dm_model_trends_candidate_share
  dm_model_trends_candidate_share <- candidate_data$dm_model_trends_candidate_share

  candidate_raw <- bind_rows(
    astro_dm_model_trends |> mutate(field = "Astrophysics"),
    dm_model_trends |> mutate(field = "High-energy physics")
  )

  candidate_norm <- bind_rows(
    astro_dm_model_trends_candidate_share,
    dm_model_trends_candidate_share
  ) |>
    mutate(field = recode(
      arxiv_category,
      "astrophysics" = "Astrophysics",
      "high-energy physics" = "High-energy physics"
    ))

  p_raw <- ggplot(candidate_raw, aes(year, n, fill = SpeciesLabel)) +
    geom_area(alpha = 0.95, linewidth = 0.15, color = "white") +
    facet_wrap(~ field, ncol = 2, scales = "free_y") +
    scale_fill_manual(values = col_map, name = NULL) +
    scale_x_continuous(
      breaks = seq(1995, 2025, 5),
      expand = expansion(mult = c(0.01, 0.01))
    ) +
    scale_y_continuous(
      labels = scales::comma_format(),
      expand = expansion(mult = c(0.01, 0.01))
    ) +
    labs(x = NULL, y = "Paper-candidate count") +
    theme_nature() +
    theme(
      strip.background = element_rect(color = "gray65", fill = NA),
      strip.text = element_text(color = "black"),
      legend.position = "none",
      axis.text.x = element_blank(),
      axis.ticks.x = element_blank(),
      axis.title.x = element_blank()
    )

  p_norm <- ggplot(candidate_norm, aes(year, share_tracked_candidates, fill = SpeciesLabel)) +
    geom_area(position = "fill", alpha = 0.95, linewidth = 0.15, color = "white") +
    facet_wrap(~ field, ncol = 2, scales = "free_y") +
    scale_fill_manual(values = col_map, name = NULL) +
    scale_x_continuous(
      breaks = seq(1995, 2025, 5),
      expand = expansion(mult = c(0.01, 0.01))
    ) +
    scale_y_continuous(
      labels = scales::percent_format(accuracy = 1),
      expand = expansion(mult = c(0.01, 0.01))
    ) +
    labs(x = NULL, y = "Share of tracked candidates") +
    theme_nature() +
    theme(
      strip.background = element_rect(fill = NA, color = NA),
      plot.margin = margin(-5, 10, 5, 10),
      legend.position = "none"
    )

  candidate_robustness <- p_raw / p_norm +
    plot_layout(widths = c(1, 1), axes = "collect_x", guides = "collect") &
    theme(
      legend.position = "right",
      legend.background = element_blank(),
      legend.key.spacing.y = grid::unit(2.2, "pt"),
      legend.text = element_text(size = 6, margin = margin(r = 0.2, unit = "pt")),
      legend.title = element_text(size = 7, family = BASE_FONT, color = "black", hjust = 0)
    )

  save_pdf(candidate_robustness, "fig_candidate_raw_vs_norm_batlow.pdf", 180, 95)

  exclude_species <- c(
    "Universal Extra Dimensions",
    "Mirror Sector",
    "Composite",
    "Vector",
    "Superfluid",
    "Asymmetric",
    "Macroscopic",
    "Planckian Interacting",
    "Scotogenic Model",
    "Twin Higgs",
    "Inert Doublet Model",
    "Inert Triplet Model",
    "Minimal~SU(2)[L]"
  )

  eps <- 0.01
  candidate_field_clean <- trend |>
    filter(
      year >= 1995,
      arxiv_category %in% c("astrophysics", "high-energy physics"),
      !is.na(SpeciesLabel),
      !SpeciesLabel %in% exclude_species
    ) |>
    distinct(year, arxiv_category, bibcode, SpeciesLabel) |>
    count(year, arxiv_category, SpeciesLabel, name = "n") |>
    group_by(year, arxiv_category) |>
    mutate(share = n / sum(n)) |>
    ungroup() |>
    select(year, arxiv_category, SpeciesLabel, share) |>
    pivot_wider(
      names_from = arxiv_category,
      values_from = share,
      values_fill = 0
    ) |>
    mutate(log_ratio_hep_astro = log2((`high-energy physics` + eps) / (`astrophysics` + eps)))

  species_order <- candidate_field_clean |>
    left_join(
      trend |>
        filter(
          year >= 1995,
          arxiv_category %in% c("astrophysics", "high-energy physics"),
          !is.na(SpeciesLabel)
        ) |>
        distinct(year, arxiv_category, bibcode, SpeciesLabel) |>
        count(year, SpeciesLabel, name = "n_total"),
      by = c("year", "SpeciesLabel")
    ) |>
    group_by(SpeciesLabel) |>
    summarise(
      mean_ratio = weighted.mean(log_ratio_hep_astro, w = n_total, na.rm = TRUE),
      .groups = "drop"
    ) |>
    arrange(mean_ratio) |>
    pull(SpeciesLabel)

  div <- c(
    "#00429d", "#2b57a7", "#426cb0", "#5681b9", "#6997c2",
    "#7daeca", "#93c4d2", "#abdad9", "#caefdf", "#ffffe0",
    "#ffe2ca", "#ffc4b4", "#ffa59e", "#f98689", "#ed6976",
    "#dd4c65", "#ca2f55", "#b11346", "#93003a"
  )

  log_ratio_plot <- candidate_field_clean |>
    mutate(SpeciesLabel = factor(SpeciesLabel, levels = species_order)) |>
    ggplot(aes(year, SpeciesLabel, fill = log_ratio_hep_astro)) +
    geom_tile(color = "white", linewidth = 0.1) +
    scale_x_continuous(
      breaks = seq(1995, 2025, 5),
      expand = expansion(mult = c(0.01, 0.0))
    ) +
    scale_fill_gradientn(
      colours = div,
      name = "Share ratio\nHEP vs. Astro",
      limits = c(-log2(10), log2(10)),
      breaks = c(-log2(10), -log2(3), 0, log2(3), log2(10)),
      labels = c("10× Astro", "3× Astro", "1×", "3× HEP", "10× HEP"),
      oob = scales::squish,
      guide = guide_colorbar(
        direction = "horizontal",
        title.position = "left",
        title.hjust = 1.0,
        title.vjust = 1.0,
        barwidth = grid::unit(70, "mm"),
        barheight = grid::unit(3.5, "mm"),
        ticks.colour = "white"
      )
    ) +
    labs(x = NULL, y = NULL) +
    theme_nature(base_size = 6) +
    theme(
      legend.title = element_text(size = 6, family = BASE_FONT, color = "black", hjust = 0),
      legend.position = "bottom"
    )

  save_pdf(log_ratio_plot, "fig_candidate_field_log_ratio.pdf", 180, 88)
}

plot_unigram_trends <- function(unigram_yearly) {
  drop_uni <- c(
    "tan", "host", "institute", "aims", "release", "datasets", "state-of-the-art",
    "potentially", "heavier", "constrain", "probed", "target", "benchmark",
    "simplified", "web", "fully", "additionally", "despite", "interestingly", "notably",
    "earlier", "thanks", "publicly", "competitive", "well-motivated", "challenging", "unexplored", "classical",
    "next-generation", "capable", "featuring", "designed", "real", "odd", "open", "rich", "deep", "projected",
    "achieved", "competitive", "revisit", "highlight", "induces", "trained", "satisfy",
    "integrated", "opens", "serves", "collected", "showing",
    "outline", "enable", "expectation", "findings", "program", "degrees", "science", "strategy",
    "article", "sets", "baseline", "band", "pairs", "utilizing", "employed", "offering", "modeling",
    "projections", "characteristics", "complexity", "questions", "impacts", "code",
    "digital", "statistical", "stacked", "unconstrained", "null", "https", "align", "cancellation", "forecast",
    "systems", "test", "sources", "times", "history", "fit",
    "state", "dependence", "spatial", "components", "functions", "mean", "average", "point", "estimates",
    "propose", "predict", "shows", "include", "conclude",
    "simulated", "dominated", "initial", "likely", "sensitive", "better", "additional",
    "local", "different", "possible", "available", "extended", "relative",
    "physical", "associated", "linear", "properties", "approach", "value", "values", "set",
    "total", "information", "size", "shape", "possibility",
    "investigate", "consider", "compared", "compare", "derived",
    "suggest", "proposed", "obtain", "explain", "measure", "given",
    "does", "produced", "future", "near", "mergers", "required", "accurate",
    "kpc", "pc", "mpc", "ev", "kev", "mev", "gev",
    "tev", "hz", "khz", "ghz", "mhz", "km", "yr", "yrs"
  )

  fit_endpoints <- function(yr, r) {
    if (sum(r > 0) < 4) return(c(NA_real_, NA_real_))
    fit <- loess(r ~ yr, span = 0.75, degree = 1, control = loess.control(surface = "direct"))
    predict(fit, newdata = data.frame(yr = c(1995, 2025)))
  }

  uni_trend <- unigram_yearly |>
    filter(!term %in% drop_uni, year >= 1995) |>
    group_by(field, term) |>
    summarise(
      n_total = sum(n_kw),
      ends = list(fit_endpoints(year, rate)),
      .groups = "drop"
    ) |>
    mutate(
      early = map_dbl(ends, 1),
      late = map_dbl(ends, 2)
    ) |>
    filter(n_total >= 40, pmax(early, late, na.rm = TRUE) >= 0.005) |>
    mutate(log_growth = log2((pmax(late, 0) + 1e-4) / (pmax(early, 0) + 1e-4)))

  uni_top_trending <- uni_trend |>
    mutate(direction = if_else(log_growth > 0, "rising", "declining")) |>
    group_by(field, direction) |>
    filter(abs(log_growth) >= 0.3) |>
    slice_max(abs(log_growth), n = 5, with_ties = FALSE) |>
    ungroup() |>
    arrange(field, direction, desc(abs(log_growth)))

  uni_ts_data <- unigram_yearly |>
    semi_join(uni_top_trending, by = c("field", "term")) |>
    left_join(
      uni_top_trending |> select(field, term, direction, log_growth),
      by = c("field", "term")
    ) |>
    filter(n_papers >= 40)

  trend_astro <- uni_ts_data |> filter(direction == "rising", field == "Astrophysics") |> distinct(term) |> pull() |> sort()
  dec_astro <- uni_ts_data |> filter(direction == "declining", field == "Astrophysics") |> distinct(term) |> pull() |> sort()
  trend_hep <- uni_ts_data |> filter(direction == "rising", field == "High-energy physics") |> distinct(term) |> pull() |> sort()
  dec_hep <- uni_ts_data |> filter(direction == "declining", field == "High-energy physics") |> distinct(term) |> pull() |> sort()

  col_map_astro <- c(
    setNames(viridis(length(trend_astro), option = "D", begin = 0.0, end = 0.95), trend_astro),
    setNames(viridis(length(dec_astro), option = "B", begin = 0.0, end = 0.9), dec_astro)
  )
  col_map_hep <- c(
    setNames(viridis(length(trend_hep), option = "D", begin = 0.0, end = 0.95), trend_hep),
    setNames(viridis(length(dec_hep), option = "B", begin = 0.0, end = 0.9), dec_hep)
  )

  astro_hdr <- patchwork::wrap_elements(grid::textGrob(
    "Astrophysics",
    x = 0.01,
    hjust = 0,
    gp = grid::gpar(fontsize = 7, fontfamily = BASE_FONT)
  ))
  hep_hdr <- patchwork::wrap_elements(grid::textGrob(
    "High-energy physics",
    x = 0.01,
    hjust = 0,
    gp = grid::gpar(fontsize = 7, fontfamily = BASE_FONT)
  ))

  uni_astro_decline <- uni_ts_data |>
    filter(direction == "declining", field == "Astrophysics") |>
    ggplot(aes(x = year, y = rate, color = term, group = term)) +
    geom_line(linewidth = 0.3, alpha = 0.35) +
    geom_smooth(se = FALSE, span = 0.75, linewidth = 0.7) +
    scale_color_manual(
      values = col_map_astro,
      name = "Decreasing",
      labels = scales::label_wrap(25),
      guide = guide_legend(
        position = "inside",
        ncol = 1,
        byrow = TRUE,
        keywidth = grid::unit(8, "pt"),
        keyheight = grid::unit(6, "pt"),
        label.position = "left",
        label.hjust = 1
      )
    ) +
    scale_x_continuous(
      breaks = seq(1995, 2025, by = 5),
      expand = expansion(mult = c(0.02, 0.02))
    ) +
    scale_y_continuous(trans = "sqrt", labels = scales::percent_format(accuracy = 1)) +
    coord_cartesian(ylim = c(0, 0.14)) +
    labs(title = NULL, x = NULL, y = "Fraction of papers (%)") +
    theme_nature() +
    theme(
      legend.position = c(0.87, 0.78),
      plot.margin = margin(0, 5, 5, 5),
      legend.background = element_blank(),
      legend.text = element_text(size = 5, margin = margin(r = 0.2, unit = "pt")),
      legend.title = element_text(size = 6, family = BASE_FONT, color = "black", hjust = 1),
      panel.grid.major.x = element_blank()
    )

  uni_astro_rising <- uni_ts_data |>
    filter(direction == "rising", field == "Astrophysics") |>
    ggplot(aes(x = year, y = rate, color = term, group = term)) +
    geom_line(linewidth = 0.3, alpha = 0.35) +
    geom_smooth(se = FALSE, span = 0.75, linewidth = 0.7) +
    scale_color_manual(
      values = col_map_astro,
      name = "Increasing",
      labels = scales::label_wrap(30),
      guide = guide_legend(
        position = "inside",
        ncol = 1,
        byrow = TRUE,
        keywidth = grid::unit(8, "pt"),
        keyheight = grid::unit(6, "pt"),
        label.position = "right",
        label.hjust = 0
      )
    ) +
    scale_x_continuous(
      breaks = seq(1995, 2025, by = 5),
      expand = expansion(mult = c(0.02, 0.02))
    ) +
    scale_y_continuous(trans = "sqrt", labels = scales::percent_format(accuracy = 1)) +
    coord_cartesian(ylim = c(0, 0.14)) +
    labs(title = NULL, x = NULL, y = NULL) +
    theme_nature() +
    theme(
      legend.position = c(0.12, 0.78),
      plot.margin = margin(0, 5, 5, 5),
      legend.background = element_blank(),
      legend.text = element_text(size = 5, margin = margin(r = 0.2, unit = "pt")),
      legend.title = element_text(size = 6, family = BASE_FONT, color = "black", hjust = 0),
      panel.grid.major.x = element_blank()
    )

  uni_hep_decline <- uni_ts_data |>
    filter(direction == "declining", field == "High-energy physics") |>
    ggplot(aes(x = year, y = rate, color = term, group = term)) +
    geom_line(linewidth = 0.3, alpha = 0.35) +
    geom_smooth(se = FALSE, span = 0.75, linewidth = 0.7) +
    scale_color_manual(
      values = col_map_hep,
      name = "Decreasing",
      labels = scales::label_wrap(25),
      guide = guide_legend(
        position = "inside",
        ncol = 1,
        byrow = TRUE,
        keywidth = grid::unit(8, "pt"),
        keyheight = grid::unit(6, "pt"),
        label.position = "left",
        label.hjust = 1
      )
    ) +
    scale_x_continuous(
      breaks = seq(1995, 2025, by = 5),
      expand = expansion(mult = c(0.02, 0.02))
    ) +
    scale_y_continuous(trans = "sqrt", labels = scales::percent_format(accuracy = 1)) +
    coord_cartesian(ylim = c(0, 0.4)) +
    labs(title = NULL, x = NULL, y = "Fraction of papers (%)") +
    theme_nature() +
    theme(
      legend.position = c(0.87, 0.78),
      plot.margin = margin(-10, 5, 5, 5),
      legend.background = element_blank(),
      legend.text = element_text(size = 5, margin = margin(r = 0.2, unit = "pt")),
      legend.title = element_text(size = 6, family = BASE_FONT, color = "black", hjust = 1),
      panel.grid.major.x = element_blank()
    )

  uni_hep_rising <- uni_ts_data |>
    filter(direction == "rising", field == "High-energy physics") |>
    ggplot(aes(x = year, y = rate, color = term, group = term)) +
    geom_line(linewidth = 0.3, alpha = 0.35) +
    geom_smooth(se = FALSE, span = 0.75, linewidth = 0.7) +
    scale_color_manual(
      values = col_map_hep,
      name = "Increasing",
      labels = scales::label_wrap(30),
      guide = guide_legend(
        position = "inside",
        ncol = 1,
        byrow = TRUE,
        keywidth = grid::unit(8, "pt"),
        keyheight = grid::unit(6, "pt"),
        label.position = "right",
        label.hjust = 0
      )
    ) +
    scale_x_continuous(
      breaks = seq(1995, 2025, by = 5),
      expand = expansion(mult = c(0.02, 0.02))
    ) +
    scale_y_continuous(trans = "sqrt", labels = scales::percent_format(accuracy = 1)) +
    coord_cartesian(ylim = c(0, 0.4)) +
    labs(title = NULL, x = NULL, y = NULL) +
    theme_nature() +
    theme(
      legend.position = c(0.19, 0.78),
      plot.margin = margin(0, 5, 5, 5),
      legend.background = element_blank(),
      legend.text = element_text(size = 5, margin = margin(r = 0.2, unit = "pt")),
      legend.title = element_text(size = 6, family = BASE_FONT, color = "black", hjust = 0),
      panel.grid.major.x = element_blank()
    )

  design <- "
  AA
  BC
  DD
  EF
  "

  uni_ngram_plot <- astro_hdr + uni_astro_decline + uni_astro_rising +
    hep_hdr + uni_hep_decline + uni_hep_rising +
    plot_layout(design = design, heights = c(0.85, 10, 0.85, 10), axes = "collect") +
    theme(plot.margin = margin(-55, 5, -25, 5))

  save_pdf(uni_ngram_plot, "fig_uni_grams_trends.pdf", 180, 100)
}

report_outputs <- function() {
  message("Wrote paper assets to:")
  message("  ", file.path(FIG_DIR, "fig_composition_batlow.pdf"))
  message("  ", file.path(FIG_DIR, "fig_candidate_raw_vs_norm_batlow.pdf"))
  message("  ", file.path(FIG_DIR, "fig_candidate_field_log_ratio.pdf"))
  message("  ", file.path(FIG_DIR, "fig_uni_grams_trends.pdf"))
  message("  ", file.path(TABLE_DIR, "table_model_terms.tex"))
}

main <- function() {
  print_stage("Load Inputs")
  ensure_output_dirs()
  inputs <- load_inputs()
  report_input_inventory(inputs)

  print_stage("Validate Inputs")
  validate_inputs(inputs)

  print_stage("Prepare Canonical Data")
  papers <- prepare_papers(inputs$papers, inputs$paper_arxiv_classes)
  candidate_long <- prepare_candidate_long(inputs$dm_candidates, papers)
  report_prepared_data(papers, candidate_long, inputs$unigram_yearly)

  print_stage("Build Candidate Figure Data")
  candidate_data <- prepare_candidate_trends(candidate_long)

  print_stage("Render Composition Figure")
  plot_composition(papers, inputs$metrics)

  print_stage("Render Candidate Figures And Table")
  write_candidate_table(candidate_data$trend, candidate_data$species)
  plot_candidate_assets(candidate_data)

  print_stage("Render Lexical Figure")
  plot_unigram_trends(inputs$unigram_yearly)

  print_stage("Finished")
  report_outputs()
  invisible(NULL)
}

if (sys.nframe() == 0) {
  main()
}
