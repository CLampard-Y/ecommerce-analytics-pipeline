# Cell 1
# =============================
# 一. 从源文件(.csv)导入数据
# =============================
# 目的: 以TEXT类型导入所有数据,先保证数据能成功导入

import os
import pandas as pd
from sqlalchemy import create_engine

# -----------------------------
# 1. 配置数据库连接
# -----------------------------
# TODO: 使用环境变量替代硬编码密码
load_dotenv()

# 从环境变量读取连接信息
DB_USER = os.getenv("DB_USER")
DB_PASS = os.getenv("DB_PASS")
DB_HOST = os.getenv("DB_HOST","localhost")
DB_PORT = os.getenv("DB_PORT","5432")
DB_NAME = os.getenv("DB_NAME")

connection_string = f"postgresql+psycopg2://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
engine = create_engine(connection_string)

# ----------------------------
# 2. 数据导入
# ----------------------------

# 请确保你的CSV文件目录
DATA_DIR = r"./data"

# 定义函数:将CSV文件加载到PostgreSQL数据库中
# 关键点强制将所有列读取为字符串,防止ID前导零丢失。
def load_csv_to_pg(csv_path: str, table_name: str, schema: str = "public", if_exists: str = "replace"):
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