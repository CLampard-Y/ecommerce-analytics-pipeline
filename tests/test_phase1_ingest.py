import os
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = ROOT / "src"
sys.path.insert(0, str(SRC_DIR))

from ecommerce_analytics_pipeline import phase1_ingest


class TestPhase1Ingest(unittest.TestCase):
    def test_main_fails_fast_when_core_csv_is_missing(self) -> None:
        with TemporaryDirectory() as tmp_dir:
            data_dir = Path(tmp_dir)
            (data_dir / "present.csv").write_text("id\n1\n", encoding="ascii")

            with patch.dict(os.environ, {"RAW_SCHEMA": "olist"}), patch.object(
                phase1_ingest, "DATA_DIR", tmp_dir
            ), patch.object(
                phase1_ingest, "iter_core_files", return_value=["present.csv", "missing.csv"]
            ), patch.object(phase1_ingest, "get_engine"), patch.object(
                phase1_ingest, "load_csv_to_pg"
            ) as mock_load:
                with self.assertRaisesRegex(FileNotFoundError, "missing.csv"):
                    phase1_ingest.main()

            mock_load.assert_not_called()

    def test_main_rejects_non_default_raw_schema(self) -> None:
        with TemporaryDirectory() as tmp_dir:
            data_dir = Path(tmp_dir)
            (data_dir / "present.csv").write_text("id\n1\n", encoding="ascii")

            with patch.dict(os.environ, {"RAW_SCHEMA": "raw"}), patch.object(
                phase1_ingest, "DATA_DIR", tmp_dir
            ), patch.object(
                phase1_ingest, "iter_core_files", return_value=["present.csv"]
            ), patch.object(phase1_ingest, "get_engine"), patch.object(
                phase1_ingest, "load_csv_to_pg"
            ) as mock_load:
                with self.assertRaisesRegex(ValueError, "RAW_SCHEMA"):
                    phase1_ingest.main()

            mock_load.assert_not_called()

    def test_load_csv_to_pg_propagates_errors(self) -> None:
        with patch.object(phase1_ingest, "ensure_schema_exists"), patch.object(
            phase1_ingest, "get_engine", return_value=object()
        ), patch("ecommerce_analytics_pipeline.phase1_ingest.pd.read_csv") as mock_read_csv:
            mock_read_csv.side_effect = ValueError("bad csv")

            with self.assertRaisesRegex(ValueError, "bad csv"):
                phase1_ingest.load_csv_to_pg("broken.csv", "broken_table")


if __name__ == "__main__":
    unittest.main()
