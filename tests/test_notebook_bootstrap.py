import os
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = ROOT / "src"
sys.path.insert(0, str(SRC_DIR))


from ecommerce_analytics_pipeline.notebook_bootstrap import bootstrap  # noqa: E402


class TestNotebookBootstrap(unittest.TestCase):
    def test_bootstrap_loads_config_and_returns_schemas(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "configs").mkdir(parents=True, exist_ok=True)

            (root / "configs" / "config.yml").write_text(
                """
paths:
  env_file: ".env"
  figures_dir: "outputs/figures/"

warehouse:
  raw_schema: "olist"
  analytics_schema: "analysis"
""".lstrip(),
                encoding="ascii",
            )

            # We don't want to create a real SQLAlchemy engine in unit tests.
            fake_engine = object()

            with patch.dict(
                os.environ,
                {
                    "DB_USER": "u",
                    "DB_PASS": "p",
                    "DB_HOST": "localhost",
                    "DB_PORT": "5432",
                    "DB_NAME": "db",
                },
                clear=True,
            ), patch(
                "ecommerce_analytics_pipeline.notebook_bootstrap.create_engine",
                return_value=fake_engine,
            ):
                ctx = bootstrap(project_root=root)

            self.assertEqual(ctx.raw_schema, "olist")
            self.assertEqual(ctx.analytics_schema, "analysis")
            self.assertTrue(ctx.figures_dir.exists())
            self.assertEqual(ctx.engine, fake_engine)

    def test_bootstrap_fails_if_env_vars_missing(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "configs").mkdir(parents=True, exist_ok=True)
            (root / "configs" / "config.yml").write_text(
                "paths:\n  env_file: '.env'\n  figures_dir: 'outputs/figures/'\n",
                encoding="ascii",
            )

            with patch.dict(os.environ, {}, clear=True):
                with self.assertRaisesRegex(RuntimeError, "Missing required env vars"):
                    bootstrap(project_root=root)

    def test_bootstrap_rejects_invalid_schema_identifier(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "configs").mkdir(parents=True, exist_ok=True)
            (root / "configs" / "config.yml").write_text(
                """
paths:
  env_file: ".env"
  figures_dir: "outputs/figures/"
warehouse:
  raw_schema: "olist"
  analytics_schema: "analysis; DROP SCHEMA analysis;"
""".lstrip(),
                encoding="ascii",
            )

            with patch.dict(
                os.environ,
                {
                    "DB_USER": "u",
                    "DB_PASS": "p",
                    "DB_HOST": "localhost",
                    "DB_PORT": "5432",
                    "DB_NAME": "db",
                },
                clear=True,
            ), patch(
                "ecommerce_analytics_pipeline.notebook_bootstrap.create_engine",
                return_value=object(),
            ):
                with self.assertRaisesRegex(ValueError, "Invalid analytics_schema"):
                    bootstrap(project_root=root)

    def test_bootstrap_rejects_non_default_raw_schema(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "configs").mkdir(parents=True, exist_ok=True)

            (root / "configs" / "config.yml").write_text(
                """
paths:
  env_file: ".env"
  figures_dir: "outputs/figures/"
warehouse:
  raw_schema: "raw"
  analytics_schema: "analysis"
""".lstrip(),
                encoding="ascii",
            )

            with patch.dict(
                os.environ,
                {
                    "DB_USER": "u",
                    "DB_PASS": "p",
                    "DB_HOST": "localhost",
                    "DB_PORT": "5432",
                    "DB_NAME": "db",
                },
                clear=True,
            ), patch(
                "ecommerce_analytics_pipeline.notebook_bootstrap.create_engine",
                return_value=object(),
            ):
                with self.assertRaisesRegex(ValueError, "Unsupported raw_schema"):
                    bootstrap(project_root=root)

    def test_bootstrap_rejects_non_default_analytics_schema(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "configs").mkdir(parents=True, exist_ok=True)

            (root / "configs" / "config.yml").write_text(
                """
paths:
  env_file: ".env"
  figures_dir: "outputs/figures/"
warehouse:
  raw_schema: "olist"
  analytics_schema: "analytics"
""".lstrip(),
                encoding="ascii",
            )

            with patch.dict(
                os.environ,
                {
                    "DB_USER": "u",
                    "DB_PASS": "p",
                    "DB_HOST": "localhost",
                    "DB_PORT": "5432",
                    "DB_NAME": "db",
                },
                clear=True,
            ), patch(
                "ecommerce_analytics_pipeline.notebook_bootstrap.create_engine",
                return_value=object(),
            ):
                with self.assertRaisesRegex(ValueError, "Unsupported analytics_schema"):
                    bootstrap(project_root=root)

    def test_bootstrap_rejects_env_raw_schema_mismatch(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "configs").mkdir(parents=True, exist_ok=True)

            (root / "configs" / "config.yml").write_text(
                """
paths:
  env_file: ".env"
  figures_dir: "outputs/figures/"
warehouse:
  raw_schema: "olist"
  analytics_schema: "analysis"
""".lstrip(),
                encoding="ascii",
            )

            with patch.dict(
                os.environ,
                {
                    "DB_USER": "u",
                    "DB_PASS": "p",
                    "DB_HOST": "localhost",
                    "DB_PORT": "5432",
                    "DB_NAME": "db",
                    "RAW_SCHEMA": "raw",
                },
                clear=True,
            ), patch(
                "ecommerce_analytics_pipeline.notebook_bootstrap.create_engine",
                return_value=object(),
            ):
                with self.assertRaisesRegex(ValueError, "RAW_SCHEMA env var must be 'olist'"):
                    bootstrap(project_root=root)


if __name__ == "__main__":
    unittest.main()
