"""Project-local path helpers for the analysis-version code bundle."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ProjectPaths:
    code_root: Path
    project_root: Path
    data_dir: Path
    stage_outputs_root: Path

    def output_dir(self, name: str) -> Path:
        path = self.stage_outputs_root / name
        path.mkdir(parents=True, exist_ok=True)
        return path


def discover_code_root(start: Path | None = None) -> Path:
    """Find the `code/` directory containing this reproducibility bundle."""
    candidates = [start or Path.cwd(), *(start or Path.cwd()).parents]
    for candidate in candidates:
        candidate = candidate.resolve()
        if (candidate / "shared").exists() and (candidate / "README.md").exists():
            return candidate
    raise FileNotFoundError("Could not locate the analysis-version code root.")


def get_project_paths(start: Path | None = None) -> ProjectPaths:
    code_root = discover_code_root(start)
    project_root = code_root.parent
    data_dir = project_root / "data"
    stage_outputs_root = code_root / "stage-outputs"
    stage_outputs_root.mkdir(parents=True, exist_ok=True)
    return ProjectPaths(
        code_root=code_root,
        project_root=project_root,
        data_dir=data_dir,
        stage_outputs_root=stage_outputs_root,
    )
