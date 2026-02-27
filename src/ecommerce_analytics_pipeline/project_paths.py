"""Centralized path helpers.

Avoids notebook-relative-path drift by anchoring all file lookups
to the repository root.
"""

from __future__ import annotations

from pathlib import Path


def project_root() -> Path:
    # src/ecommerce_analytics_pipeline/paths.py -> repo root
    return Path(__file__).resolve().parents[2]


def sql_dir() -> Path:
    return project_root() / "sql"


def outputs_dir() -> Path:
    return project_root() / "outputs"
