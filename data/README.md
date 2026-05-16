# Canonical Data Files

This directory contains the canonical machine-readable artifacts used by the manuscript pipeline.

## Canonical inputs for `code/005-build-paper-assets.R`

- `papers.parquet`
  Purpose: paper-level corpus spine used to recover publication year, abstract, and document type.

- `paper_arxiv_classes.parquet`
  Purpose: paper-to-arXiv-class mapping used to derive the primary class and primary field.

- `paper_metrics_long.parquet`
  Purpose: yearly citation-history table used for the composition figure’s impact panels.

- `dm_model_candidates_long.parquet`
  Purpose: candidate-level long table produced by `code/003-extract-dm-candidates.ipynb`, used for the candidate figures and table.

- `unigram_yearly.parquet`
  Purpose: yearly unigram rates used for `fig_uni_grams_trends.pdf`.

## Additional canonical intermediates

- `papers_with_dm_models.parquet`
  Purpose: lean paper-level DM model enrichment produced by `code/003-extract-dm-candidates.ipynb`.

## Not canonical

- Raw JSON snapshots and superseded outputs belong in `../archive/`, not here.
- Support CSV/parquet files produced for inspection by `004-build-lexical-data.ipynb` live under `../code/stage-outputs/004-build-lexical-data/`.
