"""Shared bootstrap utilities for notebooks.

This module is intentionally small and explicit: it makes notebook execution
reproducible by (1) loading `configs/config.yml`, (2) loading a local `.env`
file if present, and (3) building a SQLAlchemy engine.

We do NOT parameterize the SQL assets here; schema names remain conventions.
Notebooks can use the returned `raw_schema` / `analytics_schema` to build
schema-qualified queries consistently.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from sqlalchemy import create_engine
from sqlalchemy.engine import Engine
from sqlalchemy.engine import URL

try:
    import yaml
except Exception as exc:  # pragma: no cover
    raise ImportError(
        "Missing dependency: pyyaml. Install it via `pip install pyyaml`."
    ) from exc

try:
    from dotenv import load_dotenv
except Exception:  # pragma: no cover
    load_dotenv = None


_IDENTIFIER_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

# Guardrails: SQL assets in this repo are schema-qualified (raw `Olist.*` and
# analytics `analysis.*`). We treat schemas as fixed conventions to prevent
# silent drift between ingestion, SQL, and notebooks.
_EXPECTED_RAW_SCHEMA = "olist"
_EXPECTED_ANALYTICS_SCHEMA = "analysis"


def _validate_identifier(value: str, *, label: str) -> str:
    """Validate SQL identifier-like strings (schema names).

    This prevents accidental SQL injection via config values.
    """

    if not _IDENTIFIER_RE.fullmatch(value):
        raise ValueError(f"Invalid {label}: {value!r}")
    return value


def _resolve_project_root(project_root: Path | None) -> Path:
    if project_root is None:
        project_root = Path.cwd()
        if project_root.name == "notebooks":
            project_root = project_root.parent
    return project_root.resolve()


def _load_config(project_root: Path) -> tuple[Path, dict[str, Any]]:
    candidates = [
        project_root / "configs" / "config.yaml",
        project_root / "configs" / "config.yml",
    ]
    config_path = next((p for p in candidates if p.exists()), None)
    if config_path is None:
        raise FileNotFoundError(
            "No config file found. Searched: " + ", ".join(str(p) for p in candidates)
        )

    with open(config_path, "r", encoding="utf-8") as f:
        config = yaml.safe_load(f) or {}

    if not isinstance(config, dict):
        raise ValueError("Config must be a mapping (YAML dict).")

    return config_path, config


def _resolve_path(project_root: Path, value: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        path = project_root / path
    return path


def _build_engine_from_env() -> Engine:
    database_url = os.getenv("DATABASE_URL")
    if database_url:
        return create_engine(database_url)

    user = os.getenv("DB_USER")
    password = os.getenv("DB_PASS")
    host = os.getenv("DB_HOST", "localhost")
    port_raw = os.getenv("DB_PORT", "5432")
    db_name = os.getenv("DB_NAME")

    missing = [
        name
        for name, value in {
            "DB_USER": user,
            "DB_PASS": password,
            "DB_NAME": db_name,
        }.items()
        if not value
    ]
    if missing:
        raise RuntimeError(
            "Missing required env vars (or set DATABASE_URL): " + ", ".join(missing)
        )

    try:
        port = int(port_raw)
    except ValueError as exc:
        raise ValueError(f"Invalid DB_PORT: {port_raw!r}") from exc

    url = URL.create(
        "postgresql+psycopg2",
        username=user,
        password=password,
        host=host,
        port=port,
        database=db_name,
    )
    return create_engine(url)


@dataclass(frozen=True)
class NotebookContext:
    project_root: Path
    config_path: Path
    config: dict[str, Any]
    engine: Engine
    raw_schema: str
    analytics_schema: str
    figures_dir: Path
    env_file: Path

    def raw_table(self, table: str) -> str:
        return f"{self.raw_schema}.{table}"

    def analytics_table(self, table: str) -> str:
        return f"{self.analytics_schema}.{table}"


def bootstrap(*, project_root: Path | None = None) -> NotebookContext:
    """Load config/.env and create a SQLAlchemy engine for notebooks."""

    resolved_root = _resolve_project_root(project_root)
    config_path, config = _load_config(resolved_root)

    paths_cfg = config.get("paths", {}) or {}
    warehouse_cfg = config.get("warehouse", {}) or {}

    env_file_value = str(paths_cfg.get("env_file", ".env"))
    env_file = _resolve_path(resolved_root, env_file_value)

    # Explicitly load a local `.env` for notebooks; users can still export env vars.
    if load_dotenv is not None:
        load_dotenv(dotenv_path=env_file, override=False)

    figures_dir_value = str(paths_cfg.get("figures_dir", "outputs/figures/"))
    figures_dir = _resolve_path(resolved_root, figures_dir_value)
    figures_dir.mkdir(parents=True, exist_ok=True)

    raw_schema = _validate_identifier(
        str(warehouse_cfg.get("raw_schema", _EXPECTED_RAW_SCHEMA)), label="raw_schema"
    )
    analytics_schema = _validate_identifier(
        str(warehouse_cfg.get("analytics_schema", _EXPECTED_ANALYTICS_SCHEMA)),
        label="analytics_schema",
    )

    if raw_schema != _EXPECTED_RAW_SCHEMA:
        raise ValueError(
            "Unsupported raw_schema: "
            + repr(raw_schema)
            + ". Keep configs/config.yml warehouse.raw_schema='olist' unless you also "
            + "update the SQL assets that reference Olist.*."
        )

    if analytics_schema != _EXPECTED_ANALYTICS_SCHEMA:
        raise ValueError(
            "Unsupported analytics_schema: "
            + repr(analytics_schema)
            + ". Keep configs/config.yml warehouse.analytics_schema='analysis' unless "
            + "you also update the SQL assets that write/read analysis.*."
        )

    raw_schema_env = os.getenv("RAW_SCHEMA")
    if raw_schema_env and raw_schema_env != _EXPECTED_RAW_SCHEMA:
        raise ValueError(
            "RAW_SCHEMA env var must be 'olist' for this repo (or unset). Found: "
            + repr(raw_schema_env)
        )

    engine = _build_engine_from_env()

    return NotebookContext(
        project_root=resolved_root,
        config_path=config_path,
        config=config,
        engine=engine,
        raw_schema=raw_schema,
        analytics_schema=analytics_schema,
        figures_dir=figures_dir,
        env_file=env_file,
    )
