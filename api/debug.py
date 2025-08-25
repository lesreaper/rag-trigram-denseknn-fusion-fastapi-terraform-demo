import psycopg2
from fastapi import APIRouter
from db import DB_CONN

router = APIRouter()

@router.get("/debug/tenant/{tenant_id}")
def tenant_debug(tenant_id: str):
    conn = psycopg2.connect(**DB_CONN)
    cur = conn.cursor()
    cur.execute("SELECT count(*) FROM documents WHERE tenant_id=%s", (tenant_id,))
    count = cur.fetchone()[0]
    cur.execute("SELECT id, left(content, 200) FROM documents WHERE tenant_id=%s LIMIT 5", (tenant_id,))
    sample = cur.fetchall()
    cur.close()
    conn.close()
    return {"tenant_id": tenant_id, "count": count, "sample": sample}
