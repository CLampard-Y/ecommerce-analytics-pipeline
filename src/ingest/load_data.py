"""Legacy entrypoint (kept for backward compatibility).

The project was reorganized to an installable package under
`src/ecommerce_analytics_pipeline/`.

Preferred usage (after `pip install -e .`):
  python -m ecommerce_analytics_pipeline.ingest
"""

from __future__ import annotations

import sys
from pathlib import Path


def _ensure_src_on_path() -> None:
    # If the project is not installed editable yet, make `src/` importable.
    repo_root = Path(__file__).resolve().parents[2]
    src_dir = repo_root / "src"
    sys.path.insert(0, str(src_dir))


_ensure_src_on_path()

from ecommerce_analytics_pipeline.ingest import main  # noqa: E402


if __name__ == "__main__":
    raise SystemExit(main())
