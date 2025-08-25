import { NextRequest } from 'next/server'
export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function POST(req: NextRequest) {
  const base = process.env.FASTAPI_INTERNAL_URL!
  const headers = new Headers(req.headers)
  headers.delete('host')
  headers.delete('content-length')
  headers.set('accept', 'text/event-stream')

  const upstream = await fetch(`${base}/api/ingest/stream`, {
    method: 'POST',
    headers,
    body: req.body,         // <-- raw stream, do NOT call req.formData()
    cache: 'no-store',
    // @ts-ignore
    duplex: 'half',
  })
  if (!upstream.ok || !upstream.body) {
    const text = await upstream.text().catch(() => '')
    return new Response(text || `Upstream ${upstream.status}`, { status: upstream.status || 502 })
  }

  const { readable, writable } = new TransformStream()
  ;(async () => {
    const r = upstream.body!.getReader()
    const w = writable.getWriter()
    try {
      while (true) {
        const { value, done } = await r.read()
        if (done) break
        await w.write(value)
      }
    } finally {
      try { await w.close() } catch {}
      try { r.releaseLock() } catch {}
    }
  })()

  return new Response(readable, {
    headers: {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      'Connection': 'keep-alive',
      'X-Accel-Buffering': 'no',
    },
  })
}
