# Stage Outputs

This directory holds stage-local outputs that are useful for inspection, caching, or audit, but are **not** part of the canonical shared data contract.

Use this rule:

- `../data/` = files that later pipeline stages are allowed to depend on
- `./stage-outputs/` = files produced by a stage for local inspection or reuse inside that stage

Public bundle rule:

- the public Git repository keeps only one retained archive from `001-collect-ads-records/`: `ads_stage_001_snapshots.zip`
- other stage outputs are considered local, regenerable byproducts and are ignored by default

Examples:

- retained ADS archive from record collection
- mention-level audit tables from candidate extraction
- cached cleaned corpora and support tables from lexical analysis
