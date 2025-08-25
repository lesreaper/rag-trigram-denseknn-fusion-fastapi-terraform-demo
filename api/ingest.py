# api/ingest.py
import contextlib
import io, csv, zipfile, json, asyncio, re, requests
from io import StringIO
from typing import AsyncIterator, List, Tuple, Optional

import pandas as pd
import psycopg2
from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from fastapi.responses import StreamingResponse
from openai import AsyncOpenAI

from config import (
    OPENAI_API_KEY, EMBED_MODEL,
    EMBED_CONCURRENCY,           # e.g., 8–12
)
from utils import (
    clean_text, split_markdown_sections, simple_chunk_words,
    dedupe_nearby, normalize_numbers
)
from db import DB_CONN, insert_documents_on_conn  # add helper below
from metrics import push_ingest_metric

router = APIRouter()
client = AsyncOpenAI(api_key=OPENAI_API_KEY)

# ---- tuning knobs (safe defaults)
PANDAS_CHUNKSIZE = 400            # CSV rows per pandas chunk
EMBED_BATCH = 128                  # texts per embedding request
MIN_MICRO_BULLET = 30              # min chars to keep a bullet
MIN_TABLE_ROW   = 20               # min chars to keep a table row
MIN_PARA        = 60               # min chars for a paragraph chunk
TOK_WINDOW      = 320              # window size for main paragraphs
TOK_OVERLAP     = 24               # overlap tokens
MAX_BULLETS_PER_SECTION   = 12     # cap micro-bullets per section
MAX_TABLEROWS_PER_SECTION = 20     # cap micro table rows per section

def _rows_from_generic_csv(csv_bytes: bytes) -> List[str]:
    try:
        buf = io.StringIO(csv_bytes.decode("utf-8"))
    except UnicodeDecodeError:
        raise HTTPException(status_code=400, detail="CSV must be UTF-8")
    return [" ".join(r) for r in csv.reader(buf) if r]

def _iter_kizen_chunks_from_df(df: pd.DataFrame) -> List[str]:
    """Yield cleaned, section-aware chunks from a dataframe batch."""
    is_str = lambda v: isinstance(v, str) and v.strip() != ""
    out: List[str] = []

    for _, row in df.iterrows():
        title = row.get("metadata/title") if is_str(row.get("metadata/title")) else ""
        url = (row.get("url") if is_str(row.get("url")) else "") or \
              (row.get("crawl/loadedUrl") if is_str(row.get("crawl/loadedUrl")) else "")
        md  = row.get("markdown") if is_str(row.get("markdown")) else ""
        txt = row.get("text") if is_str(row.get("text")) else ""
        content = md if md else txt
        content = clean_text(content)
        if not content:
            continue

        sections = split_markdown_sections(content)
        for head, body in sections:
            pre = []
            if title: pre.append(f"Title: {title}")
            if url:   pre.append(f"URL: {url}")
            if head:  pre.append(f"Section: {head}")

            body = normalize_numbers(body or "")

            # bullets -> micro-chunks
            bullet_lines = []
            bcount = 0
            for ln in body.splitlines():
                if re.match(r"^\s*([*\-]|•)\s+", ln):
                    bullet = re.sub(r"^\s*([*\-]|•)\s+", "", ln).strip()
                    if len(bullet) >= MIN_MICRO_BULLET:
                        out.append(("\n".join(pre) + f"\n\nBullet: {bullet}").strip())
                        bullet_lines.append(ln)
                        bcount += 1
                        if bcount >= MAX_BULLETS_PER_SECTION: break

            # tables -> micro-chunks
            table_lines = []
            tcount = 0
            for ln in body.splitlines():
                if re.match(r"^\s*\|[-\s|]+\|\s*$", ln):
                    table_lines.append(ln)
                    continue
                if "|" in ln and ln.count("|") >= 2:
                    rowtxt = re.sub(r"^\s*\||\|\s*$", "", ln)
                    rowtxt = re.sub(r"\s*\|\s*", " | ", rowtxt)
                    if len(rowtxt) >= MIN_TABLE_ROW:
                        out.append(("\n".join(pre) + f"\n\nTableRow: {rowtxt}").strip())
                        table_lines.append(ln)
                        tcount += 1
                        if tcount >= MAX_TABLEROWS_PER_SECTION: break

            # remove micro-lines from body
            if bullet_lines or table_lines:
                drop = set(bullet_lines + table_lines)
                body = "\n".join([ln for ln in body.splitlines() if ln not in drop]).strip()

            # main paragraphs
            para = ("\n".join(pre) + "\n\n" + (body or "")).strip()
            if len(para) >= MIN_PARA:
                for ch in simple_chunk_words(para, max_tokens=TOK_WINDOW, overlap=TOK_OVERLAP):
                    if len(ch) >= MIN_PARA:
                        out.append(ch)

    # de-dup similar adjacent chunks
    out = dedupe_nearby(out, hamming_thresh=5, lookback=1500)
    return out

async def _producer_parse_csv(
    csv_bytes: bytes,
    sse_queue: "asyncio.Queue[str]",
) -> AsyncIterator[str]:
    """Stream chunks from CSV in pandas batches."""
    try:
        raw = csv_bytes.decode("utf-8")
    except UnicodeDecodeError:
        raise HTTPException(status_code=400, detail="CSV must be UTF-8")
    
    await sse_queue.put(json.dumps({"phase": "parse", "msg": "Detecting header…"}))

    # locate header line
    header_idx = None
    for i, ln in enumerate(raw.splitlines()[:10]):
        if "crawl/loadedUrl" in ln and ("markdown" in ln or "text" in ln):
            header_idx = i
            break

    # Generic fallback
    if header_idx is None:
        await sse_queue.put(json.dumps({"phase":"parse","msg":"Generic CSV detected"}))
        for row in _rows_from_generic_csv(csv_bytes):
            yield row
        return

    await sse_queue.put(json.dumps({"phase":"parse","msg":"Kizen CSV detected"}))

    # pandas in streaming mode
    first = True
    total_produced = 0

    # (optional) a smaller first chunk for faster first UI update
    PANDAS_CHUNKSIZE_FIRST = 400  # small; fast feedback
    PANDAS_CHUNKSIZE_MAIN  = PANDAS_CHUNKSIZE  # your normal (e.g., 2000)

    reader = pd.read_csv(StringIO(raw), skiprows=header_idx, chunksize=PANDAS_CHUNKSIZE_FIRST)
    for df in reader:
        chunks = _iter_kizen_chunks_from_df(df)
        await sse_queue.put(json.dumps({"phase": "chunk", "produced": len(chunks)}))
        total_produced += len(chunks)
        for ch in chunks:
            yield ch
        # swap to larger chunks after the first visible update
        if first:
            first = False
            reader = pd.read_csv(StringIO(raw), skiprows=header_idx, chunksize=PANDAS_CHUNKSIZE_MAIN)

    await sse_queue.put(json.dumps({"phase": "chunk", "total_produced": total_produced}))

async def _embed_worker(
    name: str,
    batch_q: "asyncio.Queue[Optional[List[str]]]",
    sse_queue: "asyncio.Queue[str]",
    tenant_id: str,
    conn: "psycopg2.extensions.connection",
):
    """Consumes text batches, embeds, and inserts using one shared DB conn."""
    while True:
        batch: Optional[List[str]] = await batch_q.get()
        if batch is None:
            batch_q.task_done()
            break
        try:
            await sse_queue.put(json.dumps({"phase":"embed","count":len(batch)}))
            resp = await client.embeddings.create(model=EMBED_MODEL, input=batch)
            vecs = [d.embedding for d in resp.data]
            # insert on the same connection (fast)
            insert_documents_on_conn(conn, tenant_id, batch, vecs)
            await sse_queue.put(json.dumps({"phase":"insert","count":len(batch)}))
        except Exception as e:
            await sse_queue.put(json.dumps({"status":"error","detail":f"embed/insert: {e}"}))
        finally:
            batch_q.task_done()

@router.post("/ingest/stream")
async def ingest_stream(
    tenant_id: str = Form(...),
    file: UploadFile = File(None),
    csv_url: str = Form(None),
):
    # --- load bytes
    rows_iter: Optional[AsyncIterator[str]] = None
    processed_files = []

    if file:
        content = await file.read()
        if file.filename.lower().endswith(".zip"):
            # zip with one or more csvs
            z = zipfile.ZipFile(io.BytesIO(content))
            # concatenate all CSVs into one async generator
            async def _zip_iter():
                for name in z.namelist():
                    if name.lower().endswith(".csv"):
                        csv_bytes = z.read(name)
                        # yield from sub-iter
                        async for ch in _producer_parse_csv(csv_bytes, sse_queue):
                            yield ch
            rows_iter = _zip_iter()
            processed_files = [n for n in z.namelist() if n.lower().endswith(".csv")]
        elif file.filename.lower().endswith(".csv"):
            processed_files = [file.filename]
            # defined later after sse_queue creation
            pass
        else:
            raise HTTPException(status_code=400, detail="Unsupported file type.")
    elif csv_url:
        r = requests.get(csv_url)
        if r.status_code != 200:
            raise HTTPException(status_code=400, detail=f"Failed to fetch: {csv_url}")
        processed_files = [csv_url]
        # defined later after sse_queue creation
        pass
    else:
        raise HTTPException(status_code=400, detail="No file or URL provided.")

    # --- SSE stream
    sse_queue: asyncio.Queue[str] = asyncio.Queue()
    stop_event = asyncio.Event()

    async def sse():
        await sse_queue.put(json.dumps({"status":"starting","files":processed_files}))
        # init DB connection once
        try:
            conn = psycopg2.connect(**DB_CONN)
        except Exception as e:
            await sse_queue.put(json.dumps({"status":"error","detail":f"DB connect failed: {e}"}))
            yield f"data: {json.dumps({'status':'error','detail':str(e)})}\n\n"
            return

        batch_q: asyncio.Queue[Optional[List[str]]] = asyncio.Queue(maxsize=EMBED_CONCURRENCY * 2)
        workers = [
            asyncio.create_task(_embed_worker(f"w{i+1}", batch_q, sse_queue, tenant_id, conn))
            for i in range(EMBED_CONCURRENCY)
        ]

        # choose the producer
        async def produce_batches():
            # pick source now that sse_queue exists
            nonlocal rows_iter
            if rows_iter is None:
                if file and file.filename.lower().endswith(".csv"):
                    rows_iter = _producer_parse_csv(content, sse_queue)
                elif csv_url:
                    rows_iter = _producer_parse_csv(r.content, sse_queue)

            # accumulate into EMBED_BATCH
            buf: List[str] = []
            produced = 0
            assert rows_iter is not None
            async for ch in rows_iter:
                buf.append(ch)
                if len(buf) >= EMBED_BATCH:
                    await batch_q.put(buf)
                    produced += len(buf)
                    buf = []
            if buf:
                await batch_q.put(buf)
                produced += len(buf)
            # tell workers to stop
            for _ in workers:
                await batch_q.put(None)  # signal end of batches

        # producer + streamer
        prod_task = asyncio.create_task(produce_batches())

        # SSE loop
        HEARTBEAT_SEC = 15
        last_send = asyncio.get_event_loop().time()

        try:
            while True:
                try:
                    item = await asyncio.wait_for(sse_queue.get(), timeout=1.0)
                    yield f"data: {item}\n\n"
                    last_send = asyncio.get_event_loop().time()
                except asyncio.TimeoutError:
                    now = asyncio.get_event_loop().time()
                    if now - last_send >= HEARTBEAT_SEC:
                        hb = json.dumps({"phase": "hb", "ts": int(now)})
                        yield f"data: {hb}\n\n"
                        last_send = now
                # exit when producer is done and queues are empty and workers finished
                if prod_task.done() and batch_q.empty() and all(w.done() for w in workers):
                    break
        finally:
            # wait for workers, close DB
            await prod_task
            for w in workers:
                with contextlib.suppress(Exception):
                    await w
            with contextlib.suppress(Exception):
                conn.close()

        await sse_queue.put(json.dumps({"status":"complete"}))
        yield f"data: {json.dumps({'status':'complete'})}\n\n"
        stop_event.set()

    push_ingest_metric("Start")
    return StreamingResponse(
        sse(),
        media_type="text/event-stream; charset=utf-8",
        headers={
            "Cache-Control": "no-cache, no-transform",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )
