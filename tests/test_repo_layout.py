import unittest
from pathlib import Path


class TestRepoLayout(unittest.TestCase):
    def test_expected_assets_exist(self) -> None:
        root = Path(__file__).resolve().parents[1]

        expected_paths = [
            root / "configs" / "config.yml",
            root / "sql" / "models" / "10_atomic" / "create_items_atomic.sql",
            root / "sql" / "models" / "20_obt" / "create_obt.sql",
            root / "sql" / "analyses" / "analysis_rfm.sql",
            root / "sql" / "dq" / "check_obt.sql",
            root / "notebooks" / "01_obt_feature_analysis.ipynb",
            root / "notebooks" / "02_seller_hook_analysis.ipynb",
            root / "notebooks" / "03_repurchase_diagnosis.ipynb",
            root / "src" / "ecommerce_analytics_pipeline" / "ingest.py",
            root / "src" / "ecommerce_analytics_pipeline" / "phase1_ingest.py",
            root / "src" / "ecommerce_analytics_pipeline" / "paths.py",
            root / "src" / "ecommerce_analytics_pipeline" / "project_paths.py",
            root / "src" / "ingest" / "load_data.py",
        ]

        missing = [str(p.relative_to(root)) for p in expected_paths if not p.exists()]
        self.assertEqual(missing, [], msg=f"Missing expected files: {missing}")


if __name__ == "__main__":
    unittest.main()
