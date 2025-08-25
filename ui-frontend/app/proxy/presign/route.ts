export async function GET(req: Request) {
  const qs = new URL(req.url).search; // e.g. ?ext=csv
  const upstream = `${process.env.FASTAPI_INTERNAL_URL}/api/ingest/presign${qs}`;
  const r = await fetch(upstream, { method: 'GET', cache: 'no-store' });
  const body = await r.text();
  return new Response(body, {
    status: r.status,
    headers: { 'content-type': r.headers.get('content-type') || 'application/json' },
  });
}