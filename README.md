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
---

# Analysis-Version Transparency Bundle

This directory is the public transparency bundle for the **Nature Astronomy Analysis** draft, *Phenomena, Particles, and the Plurality of Dark Matter*. It is organized around one canonical pipeline, one canonical set of shared data artifacts, and one canonical set of final figure outputs.

## Canonical pipeline

1. `code/001-collect-ads-records.ipynb`
2. `code/002-build-canonical-data.R`
3. `code/003-extract-dm-candidates.ipynb`
4. `code/004-build-lexical-data.ipynb`
5. `code/005-build-paper-assets.R`

Optional maintenance route:

- `code/001a-update-ads-records.ipynb` mirrors the collection logic in `001` and can be used to append a new year to an existing ADS snapshot without changing the downstream pipeline.

The intended flow is:

- ADS JSON retrieval and citation histories are written under `code/stage-outputs/001-collect-ads-records/`.
- In the public repo, the costly retained ADS snapshot is packaged as one zip archive under `code/stage-outputs/001-collect-ads-records/`; extract it before running `002-build-canonical-data.R`.
- `002-build-canonical-data.R` converts those JSON files into canonical parquets in `data/`.
- `003-extract-dm-candidates.ipynb` adds candidate-model outputs needed for the manuscript figures.
- `004-build-lexical-data.ipynb` writes the canonical yearly unigram parquet used by the lexical figure.
- `005-build-paper-assets.R` rebuilds the final paper figures and table from the canonical parquets only.

## Canonical directories

- `code/`: notebook-led upstream pipeline and shared helpers
- `code/stage-outputs/`: stage-local caches, audit tables, and support exports that are not part of the canonical shared data contract. In the public repo, only the retained stage-001 ADS snapshot archive is kept there by default.
- `data/`: canonical machine-readable inputs and intermediates
- `figures/`: final manuscript figure PDFs only
- `tables/`: final manuscript table fragments only

## Scope

- This public repository is about computational and methodological transparency.
- It contains the code, curated data artifacts, generated table fragment, and final figure outputs needed to inspect and reproduce the analysis.
- The retained ADS provenance snapshot is distributed as a zip archive containing a hydrated-records JSON and a citation-metrics JSON.
- The manuscript source, manuscript PDF, and bibliography are intentionally kept out of the public repository surface.

## Repository metadata

- Citation metadata: [CITATION.cff](/Users/sallz/damadi/Nature%20Astronomy/analysis-version/CITATION.cff)
- Repository license: [LICENSE](/Users/sallz/damadi/Nature%20Astronomy/analysis-version/LICENSE)
- Git line-ending and binary-file rules: [.gitattributes](/Users/sallz/damadi/Nature%20Astronomy/analysis-version/.gitattributes)
- Git ignore rules: [.gitignore](/Users/sallz/damadi/Nature%20Astronomy/analysis-version/.gitignore)

Before public release, add:

- the final repository URL and archival DOI to `CITATION.cff`

## Orientation

- Repo map and process chart source of truth: [docs/repo-map.qmd](/Users/sallz/damadi/Nature%20Astronomy/analysis-version/docs/repo-map.qmd)
- Optional rendered artifact: [docs/repo-map.html](/Users/sallz/damadi/Nature%20Astronomy/analysis-version/docs/repo-map.html)

## Fastest reproduction path

If the curated `data/` files are already present, run:

```bash
Rscript code/005-build-paper-assets.R
```

If you need to rebuild from the ADS outputs, run the full canonical pipeline in order.

Before running `code/002-build-canonical-data.R` from the retained stage-001 archive, extract:

- `code/stage-outputs/001-collect-ads-records/ads_stage_001_snapshots.zip`
