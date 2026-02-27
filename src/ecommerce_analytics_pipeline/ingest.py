"""Compatibility wrapper for ingestion.

The canonical implementation lives in `phase1_ingest.py` so that the codebase
can be narrated as phased deliverables (similar to the causal-uplift project).

Entry point remains stable:
  python -m ecommerce_analytics_pipeline.ingest
"""

from __future__ import annotations

from ecommerce_analytics_pipeline.phase1_ingest import (  # noqa: F401
    ensure_schema_exists,
    get_engine,
    iter_core_files,
    load_csv_to_pg,
    main,
)


if __name__ == "__main__":
    raise SystemExit(main())
