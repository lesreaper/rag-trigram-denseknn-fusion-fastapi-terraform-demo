import asyncio
from typing import List, Callable, Awaitable, Optional
from fastapi import HTTPException
from openai import AsyncOpenAI
from psycopg2 import OperationalError

from config import (
    OPENAI_API_KEY, EMBED_MODEL,
    MAX_TOKENS_PER_BATCH, MAX_ITEMS_PER_BATCH,
    EMBED_CONCURRENCY,
)
from utils import count_tokens, safe_truncate
from db import insert_documents  # your bulk insert helper (tenant_id, texts, vectors)

client = AsyncOpenAI(api_key=OPENAI_API_KEY)

async def embed_question(q: str) -> list[float]:
    resp = await client.embeddings.create(model=EMBED_MODEL, input=[q])
    return resp.data[0].embedding

def _prepare_rows(rows: List[str]) -> List[str]:
    """Strip, dedupe, and truncate overly-long rows to per-item token cap."""
    seen = set()
    cleaned: List[str] = []
    for r in rows:
        t = (r or "").strip()
        if not t:
            continue
        t = safe_truncate(t)  # enforce per-item cap
        if t in seen:
            continue
        seen.add(t)
        cleaned.append(t)
    return cleaned

def _make_batches(rows: List[str]) -> List[List[str]]:
    """Create batches that respect per-request token and item caps."""
    batches: List[List[str]] = []
    cur: List[str] = []
    cur_tokens = 0

    for r in rows:
        tok = count_tokens(r)
        # if adding this row would exceed either cap, flush current
        if cur and (cur_tokens + tok > MAX_TOKENS_PER_BATCH or len(cur) >= MAX_ITEMS_PER_BATCH):
            batches.append(cur)
            cur, cur_tokens = [], 0
        cur.append(r)
        cur_tokens += tok

    if cur:
        batches.append(cur)
    return batches

async def embed_and_store(
    rows: List[str],
    tenant_id: str,
    progress_cb: Optional[Callable[[int, int], Awaitable[None]]] = None,
) -> None:
    """
    Embeds rows in bounded parallel batches and inserts them.
    Continues on per-batch errors, reports progress.
    """
    # 0) sanitize + batch
    rows = _prepare_rows(rows)
    if not rows:
        return
    batches = _make_batches(rows)
    total = len(batches)
    done = 0

    sem = asyncio.Semaphore(EMBED_CONCURRENCY)
    errors: List[str] = []

    async def process_one(idx: int, batch: List[str]):
        nonlocal done
        async with sem:
            try:
                resp = await client.embeddings.create(model=EMBED_MODEL, input=batch)
                vectors = [d.embedding for d in resp.data]
                insert_documents(tenant_id, batch, vectors)  # your bulk insert
            except Exception as e:
                # accumulate error and continue; do NOT crash the stream
                errors.append(f"batch {idx+1}: {e}")
            finally:
                done += 1
                if progress_cb:
                    await progress_cb(done, total)

    # 1) run with gather
    await asyncio.gather(*(process_one(i, b) for i, b in enumerate(batches)))

    # 2) fail the request so the client sees it
    if errors:
        # not raising—let the caller send a finishing SSE message and show partial success
        # If you prefer to fail the HTTP request, raise HTTPException here.
        print("[embed_and_store] Errors:", "; ".join(errors))
        raise HTTPException(status_code=500, detail="; ".join(errors))
