"""ecommerce-analytics-pipeline setup.

This mirrors the lightweight, editable-install workflow used in
`causal-uplift-marketing`:

  pip install -e .

Once installed, notebooks and scripts can import the project package cleanly.
"""

from setuptools import find_packages, setup


setup(
    name="ecommerce-analytics-pipeline",
    version="0.1.0",
    description="ELT analytics pipeline for Olist e-commerce dataset",
    author="CLampard",
    package_dir={"": "src"},
    packages=find_packages(where="src"),
    python_requires=">=3.9",
    install_requires=[
        "pandas",
        "sqlalchemy",
        "psycopg2",
        "python-dotenv",
    ],
    extras_require={
        "dev": [
            "jupyter",
        ],
    },
)
