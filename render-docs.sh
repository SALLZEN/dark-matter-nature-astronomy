#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

render_with_quarto() {
  local src="$1"
  local dst="$2"
  local src_dir
  src_dir="$(dirname "$src")"

  (
    cd "$ROOT_DIR/$src_dir"
    quarto render "$(basename "$src")" --to gfm --output "$(basename "$dst")"
  )
}

render_with_fallback() {
  python3 - "$ROOT_DIR" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
targets = [
    root / "README.qmd",
    root / "code" / "README.qmd",
    root / "docs" / "repo-map.qmd",
]

for src in targets:
    text = src.read_text(encoding="utf-8")
    if text.startswith("---\n"):
        parts = text.split("\n---\n", 1)
        if len(parts) == 2:
            text = parts[1]
    text = text.replace("```{mermaid}", "```mermaid")
    text = text.replace("```{text}", "```text")
    text = re.sub(r"^\s*\n", "", text)
    text = "\n".join(line.rstrip() for line in text.splitlines()) + "\n"
    out = src.with_suffix(".md")
    tmp = out.with_suffix(out.suffix + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(out)
    print(f"wrote {out.relative_to(root)}")
PY
}

echo "Rendering GitHub-facing Markdown from Quarto sources..."

if command -v quarto >/dev/null 2>&1; then
  if render_with_quarto "README.qmd" "README.md" \
    && render_with_quarto "code/README.qmd" "code/README.md" \
    && render_with_quarto "docs/repo-map.qmd" "docs/repo-map.md"; then
    echo "Rendered with Quarto."
    exit 0
  fi

  echo "Quarto render failed; falling back to Markdown conversion."
else
  echo "Quarto not found; using fallback Markdown conversion."
fi

rm -f \
  "$ROOT_DIR/README.md" \
  "$ROOT_DIR/code/README.md" \
  "$ROOT_DIR/docs/repo-map.md"

render_with_fallback
echo "Rendered with fallback conversion."
