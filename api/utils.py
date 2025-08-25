import tiktoken
from config import EMBED_MODEL, MAX_TOKENS_PER_ITEM
from typing import List, Dict, Iterable, Tuple
import re, unicodedata, hashlib

# Use embedding model’s encoder
_encoder = tiktoken.encoding_for_model(EMBED_MODEL) if hasattr(tiktoken, "encoding_for_model") \
    else tiktoken.get_encoding("cl100k_base")

def _normalize_ws(s: str) -> str:
    s = (s or "").replace("\u00a0", " ")
    s = unicodedata.normalize("NFKC", s)
    # collapse whitespace
    s = re.sub(r"[ \t]+", " ", s)
    s = re.sub(r"\n{3,}", "\n\n", s)
    return s.strip()

_GARBAGE_SUBSTR = [
    "cookie", "privacy policy", "subscribe", "site navigation", "newsletter",
    "all rights reserved", "related posts", "breadcrumbs", "follow us",
    "linkedin", "twitter", "instagram", "facebook", "careers", "©", "terms of"
]
_NAV_LINE = re.compile(r"(home|about|blog|pricing|contact|careers)(\s*[›»/|•]\s*){2,}", re.I)
_PRICE_RE = re.compile(r"\$ ?(\d+(?:\.\d+)?)")
_PCT_RE   = re.compile(r"(\d{1,3})%")

def count_tokens(text: str) -> int:
    return len(_encoder.encode(text or ""))

def safe_truncate(text: str, max_tokens: int = MAX_TOKENS_PER_ITEM) -> str:
    """Truncate text to max_tokens for the embedding model."""
    toks = _encoder.encode(text or "")
    if len(toks) <= max_tokens:
        return text
    toks = toks[:max_tokens]
    return _encoder.decode(toks)

def build_context_snippets(snippets: List[Dict], max_chars: int = 12000) -> str:
    """
    Pack retrieved snippets into a bounded context string.
    Accepts list of dicts like {"id": ..., "content": "..."} or raw strings.
    Truncates to ~max_chars and numbers them [1], [2], ...
    """
    ctx_parts = []
    total = 0
    i = 0
    for snip in snippets:
        i += 1
        # Support either dicts with content or plain strings
        text = snip.get("content") if isinstance(snip, dict) else str(snip)
        if not text:
            continue
        chunk = f"[{i}] {text.strip()}\n"
        if total + len(chunk) > max_chars:
            break
        ctx_parts.append(chunk)
        total += len(chunk)
    return "".join(ctx_parts)

def clean_text(text: str) -> str:
    """Aggressive cleaner for header/footer/nav noise; keeps content & headings."""
    text = (text or "").replace("\u00a0", " ")
    text = unicodedata.normalize("NFKC", text)
    out, blank = [], 0
    for raw in text.splitlines():
        s = raw.strip()
        if not s:
            blank += 1
            if blank <= 1:
                out.append("")
            continue
        blank = 0
        low = s.lower()
        if any(x in low for x in _GARBAGE_SUBSTR):
            continue
        if _NAV_LINE.search(s):
            continue
        if re.match(r"(?i)^(table\s+of\s+contents|toc)\s*$", s):
            continue
        out.append(s)
    text = "\n".join(out)
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    return text

def split_markdown_sections(md: str) -> list[Tuple[str, str]]:
    """Return [(heading, body)], heading without leading #'s."""
    md = clean_text(md or "")
    parts, cur_head, buf = [], "", []
    for line in md.splitlines():
        if re.match(r"^#{1,6}\s", line):
            if buf:
                parts.append((cur_head.strip("# ").strip(), "\n".join(buf).strip()))
                buf = []
            cur_head = line
        else:
            buf.append(line)
    if buf:
        parts.append((cur_head.strip("# ").strip(), "\n".join(buf).strip()))
    return parts or [("", md)]

def simple_chunk_words(text: str, max_tokens: int = 280, overlap: int = 40) -> list[str]:
    """Word-window chunking good enough for demos."""
    words = (text or "").split()
    if not words:
        return []
    chunks, i = [], 0
    step = max(max_tokens - overlap, 1)
    while i < len(words):
        chunks.append(" ".join(words[i:i+max_tokens]))
        i += step
    return chunks

# --- lightweight near-duplicate filter (SimHash)
def _simhash64(s: str) -> int:
    v = [0]*64
    for tok in re.findall(r"\w+", (s or "").lower()):
        h = int(hashlib.md5(tok.encode("utf-8")).hexdigest(), 16)
        for i in range(64):
            v[i] += 1 if (h >> i) & 1 else -1
    out = 0
    for i in range(64):
        if v[i] >= 0:
            out |= (1 << i)
    return out

def dedupe_nearby(chunks: Iterable[str], hamming_thresh: int = 5, lookback: int = 1500) -> list[str]:
    keep, seen = [], []
    for c in chunks:
        sh = _simhash64(c)
        if any(bin(sh ^ sh2).count("1") <= hamming_thresh for sh2 in seen[-lookback:]):
            continue
        keep.append(c)
        seen.append(sh)
    return keep

def normalize_numbers(s: str) -> str:
    if not s: return s
    s = _PRICE_RE.sub(lambda m: f"${m.group(1)} (USD {m.group(1)})", s)
    s = _PCT_RE.sub(lambda m: f"{m.group(1)}% (percent {m.group(1)})", s)
    s = re.sub(r"\b/mo\b", " per month", s, flags=re.I)
    s = re.sub(r"\b/yr\b", " per year", s, flags=re.I)
    return s
