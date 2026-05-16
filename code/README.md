---
author: "Simon Allzén"
title: "Repository" 
subtitle: "_Phenomena, Particles, and the Plurality of Dark Matter_"
format:
  html:
    theme:
      dark: darkly
      light: flatly  #slate
    mermaid:
      theme: dark
      #filters:
      #- auto-dark
    mainfont: "Fraunces"
    fontsize: "10pt"
    #fontcolor: "#fffff2"
    #linkcolor: "#d65d0e"
    #backgroundcolor: "#282828"
    code-fold: true
    code-summary: "Show the code"
    tabset: true
    minimal: true
    max-width: "1600"
    smooth-scroll: true
    page-layout: article
    df-print: kable
editor: 
  markdown: 
    wrap: 72
---

------------------------------------------------------------------------

# Code Pipeline

This directory contains the canonical notebook-led pipeline for the
manuscript.

`stage-outputs/` is intentionally separate from `../data/`:

- `../data/` contains the canonical shared files that later stages are
  allowed to depend on.
- `./stage-outputs/` contains stage-local caches, audit tables, and
  support exports that help a stage run or be inspected, but are not
  part of the canonical pipeline contract.
- In the public repository, stage `001` is retained as a single zip
  archive containing the hydrated-records JSON and the citation-metrics
  JSON; the other stage outputs are local/regenerable and ignored by
  default.

## Run order

1.  `001-collect-ads-records.ipynb`
2.  `002-build-canonical-data.R`
3.  `003-extract-dm-candidates.ipynb`
4.  `004-build-lexical-data.ipynb`
5.  `005-build-paper-assets.R`

Optional maintenance route:

- `001a-update-ads-records.ipynb` is a yearly update notebook. It
  mirrors `001-collect-ads-records.ipynb`, writes to
  `stage-outputs/001a-update-ads-records/`, and is useful when you want
  to append a new year without rebuilding the entire ADS snapshot from
  scratch.
  
<br>

## Sequence summary


### 001-collect-ads-records.ipynb

<br>

**Purpose:**

  - Query NASA ADS for records containing the phrase `"dark matter"`.
  - Hydrate missing abstracts.
  - Fetch citation histories from `v1/metrics/detail` with
  `types=["citations"]`.


  **Writes:**

  1.  `stage-outputs/001-collect-ads-records/ads_search_all_years.json`
  2.  `stage-outputs/001-collect-ads-records/ads_search_all_years_with_abstracts.json`
  3.  `stage-outputs/001-collect-ads-records/ads_search_all_years_metrics_citations.json`
  4.  `stage-outputs/001-collect-ads-records/ads_stage_001_snapshots.zip`


*Public repo note:*

- The public bundle retains one zip archive containing the hydrated
  records JSON and the citation-metrics JSON - the extracted JSONs and
  the raw `ads_search_all_years.json` snapshot are local-only and can be
  regenerated
  
  <br>
  
  ---

  ##### **$\rightarrow$ 001a-update-ads-records.ipynb**

  **Purpose:**
  - Update an existing canonical ADS snapshot year by year without
    changing the downstream pipeline.
  - Mirror the collection, hydration, and citation-history logic used by
    `001-collect-ads-records.ipynb`.

  **Writes:**
  - Staged append outputs under `stage-outputs/001a-update-ads-records/`

<br>

------------------------------------------------------------------------

### 002-build-canonical-data.R

<br>

**Purpose:**

- Convert the staged ADS JSON outputs into the canonical parquet files
  used downstream.

  **Writes:**

  1.  `../data/papers.parquet`
  2.  `../data/paper_arxiv_classes.parquet`
  3.  `../data/paper_metrics_long.parquet`

*Public repo note:*

- If the extracted stage-001 JSON files are absent, unzip
  `stage-outputs/001-collect-ads-records/ads_stage_001_snapshots.zip`
  before running this stage

<br>

------------------------------------------------------------------------

### 003-extract-dm-candidates.ipynb

<br>

  **Purpose:**
  
  - Clean abstracts for candidate extraction.
  - Build the paper-level and candidate-level DM model outputs used by the
  manuscript figures.

  
  **Reads:**

  1.  `../data/papers.parquet`
  2.  `../data/paper_arxiv_classes.parquet`

  **Writes:**

  1.  `../data/papers_with_dm_models.parquet`
  2.  `../data/dm_model_candidates_long.parquet`
  3.  `stage-outputs/003-extract-dm-candidates/dm_model_mentions.parquet`
  4.  `stage-outputs/003-extract-dm-candidates/dm_model_counts_by_year.parquet`

*Public repo note:*

- The mention-level and yearly audit outputs are local inspection files
  and are not tracked in the public bundle

<br>

------------------------------------------------------------------------

### 004-build-lexical-data.ipynb

<br>

  **Purpose:**
  
  1.  Build the cleaned abstract corpus for lexical comparison.
  2.  Produce support TF-IDF and keyness tables.
  3.  Write the canonical yearly unigram parquet used by the manuscript
  figure pipeline.


  **Reads:**
  
  1.  `../data/papers.parquet`
  2.  `../data/paper_arxiv_classes.parquet`

  **Writes:**

  1.  `../data/unigram_yearly.parquet`
  2.  support outputs under
      `stage-outputs/004-build-lexical-data/support/`
  3.  cached cleaned corpus under
      `stage-outputs/004-build-lexical-data/cache/`

*Public repo note:* 

- The support CSV/parquet files and lexical caches are
local/regenerable and are not tracked in the public bundle.

<br>
<br>


## Shared helpers

- `shared/ads_api.py`: ADS query, hydration, citation-metrics, and JSON
  helpers
- `shared/normalization.py`: shared text normalization utilities
- `shared/project_paths.py`: project-local path helpers
- `tfidf/`: local preprocessing and TF-IDF configuration

## Environment

##### Python

The notebooks expect a Python environment with:

- `beautifulsoup4`
- `matplotlib`
- `numpy`
- `pandas`
- `plotly`
- `pyarrow`
- `requests`
- `scikit-learn`
- `tqdm`


##### R

The merger script expects an R environment with:

- `arrow`
- `dplyr`
- `jsonlite`
- `purrr`
- `stringr`
- `tibble`
- `tidyr`
