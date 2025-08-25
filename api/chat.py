import re
from typing import List

import psycopg2
from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from openai import AsyncOpenAI

from config import (
    OPENAI_API_KEY,
    EMBED_MODEL,
    ANSWER_MODEL,
    ANSWER_TEMPERATURE,
    MAX_CONTEXT_CHARS,
)
from db import DB_CONN
from utils import build_context_snippets

router = APIRouter()
client = AsyncOpenAI(api_key=OPENAI_API_KEY)


def rr_fusion_many(results_lists, k: int = 40):
    scores = {}
    for results in results_lists:
        for rank, row in enumerate(results, start=1):
            rid = row[0]
            scores[rid] = scores.get(rid, 0.0) + 1.0 / (k + rank)
    return sorted(scores.items(), key=lambda x: x[1], reverse=True)


def to_vector_literal(vec: List[float]) -> str:
    # pgvector literal: "[0.12,0.34,...]"
    return "[" + ",".join(f"{x:.6f}" for x in vec) + "]"


@router.post("/chat/stream")
async def chat_stream(payload: dict):
    q = payload.get("q")
    tenant_id = payload.get("tenant_id")

    if not q or not tenant_id:
        raise HTTPException(status_code=400, detail="Missing q or tenant_id")

    try:
        # 1) embed query
        emb_resp = await client.embeddings.create(model=EMBED_MODEL, input=[q])
        q_emb = emb_resp.data[0].embedding
        q_vec = to_vector_literal(q_emb)

        # numeric-aware LIKE variant (helps for pricing queries)
        num_norm_q = re.sub(r"[^0-9a-zA-Z %$]", " ", q or "")
        num_norm_q = re.sub(r"\s+", " ", num_norm_q).strip()

        # 2) retrieve (trigram + dense + ILIKEs)
        conn = psycopg2.connect(**DB_CONN)
        cur = conn.cursor()

        # trigram similarity on text
        cur.execute(
            """
            SELECT id, content
            FROM documents
            WHERE tenant_id = %s
            ORDER BY similarity(content, %s) DESC
            LIMIT 15
            """,
            (tenant_id, q),
        )
        trigram_hits = cur.fetchall()

        # dense ANN
        cur.execute(
            f"""
            SELECT id, content
            FROM documents
            WHERE tenant_id = %s
            ORDER BY embedding <-> %s::vector
            LIMIT 15
            """,
            (tenant_id, q_vec),
        )
        dense_hits = cur.fetchall()

        # ILIKE exact-ish
        like_q = f"%{q.strip()}%"
        cur.execute(
            """
            SELECT id, content
            FROM documents
            WHERE tenant_id = %s AND content ILIKE %s
            LIMIT 20
            """,
            (tenant_id, like_q),
        )
        ilike_hits = cur.fetchall()

        # numeric-aware ILIKE
        like_q2 = f"%{num_norm_q}%"
        cur.execute(
            """
            SELECT id, content
            FROM documents
            WHERE tenant_id = %s AND content ILIKE %s
            LIMIT 20
            """,
            (tenant_id, like_q2),
        )
        ilike_numeric_hits = cur.fetchall()

        cur.close()
        conn.close()

        fused = rr_fusion_many(
            [trigram_hits, dense_hits, ilike_hits, ilike_numeric_hits], k=40
        )
        id_to_text = {
            rid: text
            for rid, text in trigram_hits + dense_hits + ilike_hits + ilike_numeric_hits
        }

        # take top 12 unique
        top_ids, seen = [], set()
        for rid, _ in fused:
            if rid in seen:
                continue
            seen.add(rid)
            top_ids.append(rid)
            if len(top_ids) == 12:
                break

        snippets = [{"id": rid, "content": id_to_text[rid]} for rid in top_ids]

        if not snippets:
            async def nohit():
                yield "I don’t know. No relevant context found.".encode("utf-8")
            return StreamingResponse(nohit(), media_type="text/plain; charset=utf-8")

        # 3) build grounded prompt
        ctx = build_context_snippets(snippets, max_chars=MAX_CONTEXT_CHARS)
        system = (
            "You are a helpful assistant. Answer concisely using ONLY the provided context snippets. "
            "If the answer is not in the context, say you don't know. Include no made-up facts."
        )
        user = (
            f"Tenant: {tenant_id}\n"
            f"Question: {q}\n\n"
            f"Context snippets:\n{ctx}\n"
            "Instructions:\n"
            "- Cite snippets by their bracketed numbers, e.g., [1], [2].\n"
            "- Keep the answer to 10-15 sentences unless asked otherwise."
        )

        async def llm_stream():
            stream = await client.chat.completions.create(
                model=ANSWER_MODEL,
                temperature=ANSWER_TEMPERATURE,
                stream=True,
                messages=[
                    {"role": "system", "content": system},
                    {"role": "user", "content": user},
                ],
            )
            async for chunk in stream:
                delta = chunk.choices[0].delta
                if delta and delta.content:
                    yield delta.content

        return StreamingResponse(llm_stream(), media_type="text/plain; charset=utf-8")

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Chat failed: {e}")
