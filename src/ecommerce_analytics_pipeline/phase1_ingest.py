"""CSV -> Postgres ingestion for the Olist dataset.

Environment variables:
- Optional convenience: DATABASE_URL
- Or: DB_USER, DB_PASS, DB_HOST (default localhost), DB_PORT (default 5432), DB_NAME

Optional:
- DATA_DIR (default ./data)
- RAW_SCHEMA (default olist; aligns with sql/ models)

NOTE:
- This repo's downstream SQL assets are schema-qualified (raw `Olist.*` and
  analytics `analysis.*`). To prevent silent metric drift, we treat schemas as
  fixed conventions: keep RAW_SCHEMA='olist'.
"""

from __future__ import annotations

import os
import re
from typing import Iterable

import pandas as pd
from sqlalchemy import create_engine, text

try:
    # Optional in case the user doesn't want .env files.
    from dotenv import load_dotenv
except Exception:  # pragma: no cover
    load_dotenv = None

if load_dotenv is not None:
    load_dotenv()


_ENGINE = None


_EXPECTED_RAW_SCHEMA = "olist"


def get_engine():
    """Create and cache a SQLAlchemy engine.

    Importing this module should not require DB env vars; only calling
    ingestion functions should.
    """

    global _ENGINE
    if _ENGINE is not None:
        return _ENGINE

    database_url = os.getenv("DATABASE_URL")
    if database_url:
        _ENGINE = create_engine(database_url)
        return _ENGINE

    # Fallback: build a Postgres URL from discrete env vars.
    db_user = os.getenv("DB_USER")
    db_pass = os.getenv("DB_PASS")
    db_host = os.getenv("DB_HOST", "localhost")
    db_port = os.getenv("DB_PORT", "5432")
    db_name = os.getenv("DB_NAME")

    missing = [
        name
        for name, value in {
            "DB_USER": db_user,
            "DB_PASS": db_pass,
            "DB_NAME": db_name,
        }.items()
        if not value
    ]
    if missing:
        raise RuntimeError(
            "Missing required env vars (or set DATABASE_URL): " + ", ".join(missing)
        )

    connection_string = (
        f"postgresql+psycopg2://{db_user}:{db_pass}@{db_host}:{db_port}/{db_name}"
    )
    _ENGINE = create_engine(connection_string)
    return _ENGINE

# ----------------------------
# 2. 数据导入
# ----------------------------

# 请确保你的CSV文件目录
DATA_DIR = os.getenv("DATA_DIR", "./data")


def _validate_identifier(value: str, *, label: str) -> str:
    # Prevent accidental injection in CREATE SCHEMA; schema names should be identifiers.
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", value):
        raise ValueError(f"Invalid {label}: {value!r}")
    return value


def ensure_schema_exists(schema: str) -> None:
    schema = _validate_identifier(schema, label="schema")
    engine = get_engine()
    with engine.begin() as conn:
        conn.execute(text(f"CREATE SCHEMA IF NOT EXISTS {schema}"))

# 定义函数:将CSV文件加载到PostgreSQL数据库中
# 关键点强制将所有列读取为字符串,防止ID前导零丢失。
def load_csv_to_pg(
    csv_path: str,
    table_name: str,
    schema: str = "olist",
    if_exists: str = "replace",
) -> None:
    ensure_schema_exists(schema)

    engine = get_engine()

    # 关键：很多 ID 列必须按字符串读
    df = pd.read_csv(csv_path, dtype=str)

    # 分块写入，避免内存溢出
    df.to_sql(
        table_name,
        engine,
        schema=schema,
        if_exists=if_exists,
        index=False,
        chunksize=20000,
        method="multi",
    )
    print(f"Successfully loaded: {table_name}")


def iter_core_files() -> Iterable[str]:
    return [
        "olist_orders_dataset.csv",
        "olist_customers_dataset.csv",
        "olist_order_items_dataset.csv",
        "olist_order_payments_dataset.csv",
        "olist_order_reviews_dataset.csv",
        "olist_products_dataset.csv",
        "olist_sellers_dataset.csv",
        "product_category_name_translation.csv",
    ]


def main() -> int:
    # Fail fast if DB credentials or core CSV files are missing.
    get_engine()

    raw_schema = os.getenv("RAW_SCHEMA", _EXPECTED_RAW_SCHEMA)
    raw_schema = _validate_identifier(raw_schema, label="RAW_SCHEMA")
    if raw_schema != _EXPECTED_RAW_SCHEMA:
        raise ValueError(
            "Unsupported RAW_SCHEMA: "
            + repr(raw_schema)
            + ". This repo assumes RAW_SCHEMA='olist' because downstream SQL assets "
            + "are schema-qualified (Olist.* -> olist). If you really need a different "
            + "raw schema, update the SQL assets and configs/config.yml together."
        )
    core_files = list(iter_core_files())
    missing_files = [
        os.path.join(DATA_DIR, filename)
        for filename in core_files
        if not os.path.exists(os.path.join(DATA_DIR, filename))
    ]

    if missing_files:
        missing_display = ", ".join(missing_files)
        raise FileNotFoundError(f"Missing required CSV files: {missing_display}")

    for filename in core_files:
        csv_path = os.path.join(DATA_DIR, filename)
        table_name = os.path.splitext(filename)[0]

        load_csv_to_pg(csv_path, table_name, schema=raw_schema, if_exists="replace")

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
