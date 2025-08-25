import { NextResponse } from 'next/server'
export const runtime = 'nodejs'
export async function GET() {
  const base = process.env.FASTAPI_INTERNAL_URL
  if (!base) return NextResponse.json({ ok: false, reason: 'FASTAPI_INTERNAL_URL not set' }, { status: 500 })
  const r = await fetch(`${base}/health`).catch(e => ({ ok: false, status: 502, text: () => Promise.resolve(String(e)) }) as any)
  if (!r.ok) return NextResponse.json({ ok:false, upstream:r.status }, { status: 502 })
  return NextResponse.json(await r.json())
}