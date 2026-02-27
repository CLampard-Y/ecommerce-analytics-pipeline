"""ecommerce_analytics_pipeline.

Small, interview-friendly ELT analytics project:
- Ingest: CSV -> Postgres
- Warehouse: SQL models (atomic -> OBT)
- Analytics: notebooks consuming `analysis.*` tables
"""

__all__ = ["__version__"]

__version__ = "0.1.0"
