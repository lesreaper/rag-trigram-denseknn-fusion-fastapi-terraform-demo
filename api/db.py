import psycopg2
from psycopg2.extras import execute_values
from config import POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD

DB_CONN = {
    "host": POSTGRES_HOST,
    "port": POSTGRES_PORT,
    "dbname": POSTGRES_DB,
    "user": POSTGRES_USER,
    "password": POSTGRES_PASSWORD
}

def _vec_literal(v):
    # pgvector format: [0.12,0.34,...]
    return "[" + ",".join(f"{x:.6f}" for x in v) + "]"

def insert_documents(tenant_id, texts, embeddings):
    rows = [(tenant_id, t, _vec_literal(e)) for t, e in zip(texts, embeddings)]
    conn = psycopg2.connect(**DB_CONN)
    cur = conn.cursor()
    # cast the 3rd placeholder to vector
    execute_values(
        cur,
        "INSERT INTO documents (tenant_id, content, embedding) VALUES %s",
        rows,
        template="(%s, %s, %s::vector)"
    )
    conn.commit()
    cur.close()
    conn.close()

# api/db.py (add at bottom)
from psycopg2.extras import execute_values


def insert_documents_on_conn(conn, tenant_id, texts, embeddings):
    if not texts:
        return
    rows = [(tenant_id,
             t,
             "[" + ",".join(f"{x:.6f}" for x in e) + "]") for t, e in zip(texts, embeddings)]
    with conn.cursor() as cur:
        execute_values(
            cur,
            "INSERT INTO documents (tenant_id, content, embedding) VALUES %s",
            rows,
            template="(%s, %s, %s::vector)",
            page_size=1000,
        )
    conn.commit()

