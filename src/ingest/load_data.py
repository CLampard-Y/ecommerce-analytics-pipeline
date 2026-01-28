import os
import pandas as pd
from sqlalchemy import create_engine

# 配置数据库连接
# TODO: 使用环境变量替代硬编码密码
DB_USER = "web3"
DB_PASS = "password"  # 请确保这里是你本地真实的密码
DB_HOST = "localhost"
DB_PORT = "5432"
DB_NAME = "web3data"

connection_string = f"postgresql+psycopg2://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
engine = create_engine(connection_string)

# 数据目录配置
DATA_DIR = r"./data"  # 请确保你的 CSV 文件在这个目录下

def load_csv_to_pg(csv_path: str, table_name: str, schema: str = "public", if_exists: str = "replace"):
    """
    将 CSV 文件加载到 PostgreSQL 数据库中。
    关键点：强制将所有列读取为字符串，防止 ID 前导零丢失。
    """
    try:
        # 关键：很多 ID 列必须按字符串读
        df = pd.read_csv(csv_path, dtype=str)
        
        # 分块写入，避免内存溢出
        df.to_sql(table_name, engine, schema=schema, if_exists=if_exists, index=False, chunksize=20000, method="multi")
        print(f"Successfully loaded: {table_name}")
    except Exception as e:
        print(f"Failed to load {table_name}: {e}")

if __name__ == "__main__":
    # 定义核心文件列表
    core_files = [
        "olist_orders_dataset.csv",
        "olist_customers_dataset.csv",
        "olist_order_items_dataset.csv",
        "olist_order_payments_dataset.csv",
        "olist_order_reviews_dataset.csv",
        "olist_products_dataset.csv",
        "olist_sellers_dataset.csv",
        "product_category_name_translation.csv",
    ]

    for f in core_files:
        p = os.path.join(DATA_DIR, f)
        # 提取文件名作为表名 (去掉 .csv)
        t = os.path.splitext(f)[0]
        # 建议存入 'olist' schema (如果已创建)，否则存入 'public'
        load_csv_to_pg(p, t, schema="public", if_exists="replace")