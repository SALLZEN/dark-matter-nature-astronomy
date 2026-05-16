# Repository
Simon Allzén

## Repo Map

This document gives a structural and process-level map of the
`dark-matter-nature-astronomy` transparency bundle.

## At a Glance

The repo is organized around three ideas:

- `code/` contains the canonical pipeline stages and shared code.
- `data/` contains the canonical shared artifacts that downstream stages
  may rely on.
- `code/stage-outputs/` contains stage-local caches, audit tables, and
  support exports that are useful for inspection but are not part of the
  canonical shared contract. In the public repository, only the retained
  stage-001 ADS snapshot archive is kept there by default.

## Repository Structure

``` {text}
dark-matter-nature-astronomy/
├── .editorconfig
├── .gitattributes
├── .gitignore
├── LICENSE
├── README.md
├── README.qmd
├── CITATION.cff
│
├── code/
│   ├── README.md
│   ├── README.qmd
│   ├── 001-collect-ads-records.ipynb
│   ├── 001a-update-ads-records.ipynb
│   ├── 002-build-canonical-data.R
│   ├── 003-extract-dm-candidates.ipynb
│   ├── 004-build-lexical-data.ipynb
│   ├── 005-build-paper-assets.R
│   ├── shared/
│   │   ├── ads_api.py
│   │   ├── normalization.py
│   │   └── project_paths.py
│   ├── tfidf/
│   │   ├── preproc_utils.py
│   │   ├── tfidf_config.json
│   │   └── final_stopwords.txt
│   └── stage-outputs/
│       ├── README.md
│       ├── 001-collect-ads-records/
│       │   └── ads_stage_001_snapshots.zip
│       ├── 001a-update-ads-records/
│       │   ├── .gitkeep
│       │   └── local update snapshots are created here when the maintenance notebook is used
│       ├── 003-extract-dm-candidates/
│       │   └── local audit outputs are regenerated here when needed
│       └── 004-build-lexical-data/
│           ├── cache/
│           │   └── local cache files are regenerated here when needed
│           └── support/
│               └── local support tables are regenerated here when needed
│
├── data/
│   └── README.md
│
├── figures/
│   ├── README.md
│   ├── fig_composition_batlow.pdf
│   ├── fig_candidate_raw_vs_norm_batlow.pdf
│   ├── fig_candidate_field_log_ratio.pdf
│   └── fig_uni_grams_trends.pdf
│
├── tables/
│   ├── README.md
│   └── table_model_terms.tex
│
└── docs/
    ├── repo-map.md
    ├── repo-map.qmd
    └── rendered Markdown is generated from repo-map.qmd for GitHub display
```

## Structure Chart

The first chart shows the major top-level zones. The second opens up
`code/` so the stage layout is easier to read.

``` mermaid


flowchart LR
    R["dark-matter-nature-astronomy/"]

    R ---> C["code/"]
    R ---> F["figures/"]
    R ---> T["tables/"]
    R ---> DOC["docs/"]
    R ---> META["repo metadata"]
    R ----> D["data/"]
    
    C --> SH["shared/"]
    C --> TF["tfidf/"]
    C --> SO["stage-outputs/"]
    C ----> SC
    
    SH ---> SHA
  
    style SC fill:none,stroke-width:2px,stroke-dasharray: 5 5
    style SHA fill:none,stroke-width:2px, stroke-dasharray: 5 5
    style DATA fill:none,stroke-width:2px, stroke-dasharray: 5 5
   
      subgraph SC["scripts and notebook"]
        direction TB
        P1["001 Collect ADS records"] --> P2["002 Build canonical data"]
        P2 --> P3["003 Extract DM candidates"]
        P3 --> P4["004 Build lexical data"]
        P4 --> P5["005 Build paper assets"]
      end
    
    
      subgraph SHA["shared/"]
      direction TB
          SH1["ads_api.py"] ~~~ SH2["normalization.py"]
          SH2 ~~~ SH3["project_paths.py"]
      end
        
    TF --> TF1["preproc_utils.py"]
    TF --> TF2["tfidf_config.json"]
    TF --> TF3["final_stopwords.txt"]

    SO --> SO1["001 retained ADS snapshot archive"]
    SO --> SO1A["001a update snapshots"]
    SO --> SO3["003 audit outputs"]
    SO --> SO4["004 cache and support tables"]

    D --> DATA
      subgraph DATA["data/"]
        direction TB
        D1["papers.parquet"]
        D2["paper_arxiv_classes.parquet"]
        D3["paper_metrics_long.parquet"]
        D4["papers_with_dm_models.parquet"]
        D5["dm_model_candidates_long.parquet"]
        D6["unigram_yearly.parquet"]
        D1 ~~~ D2
        D2 ~~~ D3
        D3 ~~~ D4
        D4 ~~~ D5
        D5 ~~~ D6
      end
      
    F --> F1["final figure PDFs"]
    T --> T1["table_model_terms.tex"]
    DOC --> DOC1["repo-map.qmd / repo-map.md"]
    META --> META1["LICENSE / CITATION.cff / .gitignore / .gitattributes"]
```

<br>

## Canonical Process Flow

``` mermaid
flowchart LR
    S1["001-collect-ads-records.ipynb"] --> O1["stage-outputs/001-collect-ads-records/<br/>retained zip archive with<br/>hydrated-records JSON<br/>and citation-metrics JSON"]

    O1 --> S2["002-build-canonical-data.R"]
    S2 --> D1["data/papers.parquet"]
    S2 --> D2["data/paper_arxiv_classes.parquet"]
    S2 --> D3["data/paper_metrics_long.parquet"]

    D1 --> S3["003-extract-dm-candidates.ipynb"]
    D2 --> S3
    S3 --> D4["data/papers_with_dm_models.parquet"]
    S3 --> D5["data/dm_model_candidates_long.parquet"]
    S3 --> O3["stage-outputs/003-extract-dm-candidates/<br/>mention audit parquet<br/>yearly candidate-count parquet"]

    D1 --> S4["004-build-lexical-data.ipynb"]
    D2 --> S4
    S4 --> D6["data/unigram_yearly.parquet"]
    S4 --> O4["stage-outputs/004-build-lexical-data/<br/>cache/master abstract corpus<br/>support TF-IDF, keyness, and bigram tables"]

    D1 --> S5["005-build-paper-assets.R"]
    D2 --> S5
    D3 --> S5
    D5 --> S5
    D6 --> S5

    S5 --> F1["figures/fig_composition_batlow.pdf"]
    S5 --> F2["figures/fig_candidate_raw_vs_norm_batlow.pdf"]
    S5 --> F3["figures/fig_candidate_field_log_ratio.pdf"]
    S5 --> F4["figures/fig_uni_grams_trends.pdf"]
    S5 --> T1["tables/table_model_terms.tex"]
```

------------------------------------------------------------------------

### Interpretation Guide

- If a file is in `data/`, a later stage is allowed to depend on it.
- In the public repository, `data/` starts mostly empty and is populated
  locally by the pipeline.
- If a file is in `code/stage-outputs/`, it is useful for inspection or
  caching, but should not become a hidden dependency of a later stage.
- In the public repository, the only tracked stage-output data are the
  retained stage-001 ADS snapshot archive and its README/.gitkeep
  scaffolding.
- `figures/` contains the final figure PDFs included in the transparency
  bundle.
- `tables/` contains the generated table fragment used to summarize
  candidate terms.
