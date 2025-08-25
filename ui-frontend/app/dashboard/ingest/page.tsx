'use client'
import { useEffect, useRef, useState } from 'react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Loader2 } from 'lucide-react'

type SseMsg =
  | { status: 'starting'; files: string[] }
  | { status: 'complete' }
  | { status: 'error'; detail?: string }
  | { phase: 'parse'; msg: string }
  | { phase: 'chunk'; produced?: number; total_produced?: number }
  | { phase: 'embed'; count: number }
  | { phase: 'insert'; count: number }
  | { phase: 'hb'; ts?: number } // heartbeat

export default function IngestPage() {
  const [file, setFile] = useState<File | null>(null)
  const [url, setUrl] = useState('')

  // headline + step text
  const [status, setStatus] = useState<string>('')     // top-line status
  const [phase, setPhase] = useState<string>('')       // “Parsing… / Embedding…”
  const [details, setDetails] = useState<string>('')   // small muted line

  // running counters
  const [produced, setProduced] = useState<number>(0)  // chunks created by cleaner
  const [embedded, setEmbedded] = useState<number>(0)  // items sent to embed API
  const [inserted, setInserted] = useState<number>(0)  // rows inserted into DB
  const totalProducedRef = useRef<number>(0)           // final total from backend

  // upload + ingest progress
  const [uploadPercent, setUploadPercent] = useState<number>(0)
  const [percent, setPercent] = useState<number>(0)
  const [loading, setLoading] = useState<boolean>(false)

  // cancel handles
  const sseAbortRef = useRef<AbortController | null>(null)
  const uploadXhrRef = useRef<XMLHttpRequest | null>(null)

  const tenant = 'demo' // adjust if needed

  useEffect(() => {
    return () => {
      sseAbortRef.current?.abort()
      try { uploadXhrRef.current?.abort() } catch {}
    }
  }, [])

  // recompute ingest % whenever counters change
  const updatePercent = () => {
    const total = totalProducedRef.current || produced || embedded || inserted
    if (!total) return
    const p = Math.min(100, Math.round((inserted / total) * 100))
    setPercent(p)
  }
  useEffect(() => { updatePercent() }, [produced, embedded, inserted])

  // ---------- helpers: presign & upload ----------
  function contentTypeForExt(ext: string) {
    switch (ext) {
      case 'zip': return 'application/zip'
      case 'csv': return 'text/csv'
      default:    return 'application/octet-stream'
    }
  }

  async function getPresign(ext = 'csv'): Promise<{ put_url: string; get_url: string }> {
    const r = await fetch(`/proxy/ingest/presign?ext=${encodeURIComponent(ext)}`, { cache: 'no-store' })
    if (!r.ok) throw new Error(`presign failed: ${r.status}`)
    return r.json()
  }

  function uploadToS3(putUrl: string, file: File, contentType: string, onProgress?: (pct: number) => void) {
    return new Promise<void>((resolve, reject) => {
      const xhr = new XMLHttpRequest()
      uploadXhrRef.current = xhr
      xhr.open('PUT', putUrl, true)
      xhr.setRequestHeader('Content-Type', contentType)
      xhr.upload.onprogress = (e) => {
        if (e.lengthComputable && onProgress) {
          onProgress(Math.round((e.loaded / e.total) * 100))
        }
      }
      xhr.onerror = () => reject(new Error('upload error'))
      xhr.onload = () => {
        if (xhr.status >= 200 && xhr.status < 300) resolve()
        else reject(new Error(`upload ${xhr.status}`))
      }
      xhr.send(file)
    })
  }

  // ---------- SSE ingest ----------
  async function startIngest(csvUrl: string, controller: AbortController) {
    const form = new FormData()
    form.append('tenant_id', tenant)
    form.append('csv_url', csvUrl)

    const resp = await fetch('/proxy/ingest/stream', {
      method: 'POST',
      body: form,
      headers: { Accept: 'text/event-stream' },
      signal: controller.signal,
      cache: 'no-store',
      credentials: 'same-origin',
    })
    if (!resp.ok || !resp.body) {
      const errText = await resp.text().catch(() => '')
      throw new Error(errText || `HTTP ${resp.status}`)
    }

    const reader = resp.body.getReader()
    const decoder = new TextDecoder()
    let buffer = ''

    while (true) {
      const { done, value } = await reader.read()
      if (done) break
      buffer += decoder.decode(value, { stream: true })

      // split on \n\n to get complete SSE events
      let sep = buffer.indexOf('\n\n')
      while (sep !== -1) {
        const rawEvent = buffer.slice(0, sep).trim()
        buffer = buffer.slice(sep + 2)
        sep = buffer.indexOf('\n\n')

        for (const line of rawEvent.split('\n')) {
          const trimmed = line.trim()
          if (!trimmed.startsWith('data:')) continue
          const jsonStr = trimmed.replace(/^data:\s*/, '')

          try {
            const msg = JSON.parse(jsonStr) as SseMsg

            // ---- STATUS ----
            if ('status' in msg) {
              if (msg.status === 'starting') {
                setStatus('Uploading & parsing…')
                setPhase('Parsing CSV')
                setDetails(Array.isArray(msg.files) ? `Files: ${msg.files.join(', ')}` : '')
              } else if (msg.status === 'complete') {
                setStatus('✅ Ingestion complete')
                setPhase('')
                setPercent(100)
              } else if (msg.status === 'error') {
                setStatus('❌ Error during ingestion')
                setPhase('Error')
                setDetails(msg.detail ?? '')
              }
              continue
            }

            // ---- PHASE ----
            if ('phase' in msg) {
              switch (msg.phase) {
                case 'parse': {
                  setStatus('Parsing file…')
                  setPhase(`Parsing… ${'msg' in msg ? (msg as any).msg : ''}`)
                  break
                }
                case 'chunk': {
                  setStatus('Cleaning & splitting…')
                  setPhase('Chunking / cleaning…')
                  if ('produced' in msg && typeof msg.produced === 'number') {
                    setProduced(prev => prev + msg.produced!)
                  }
                  if ('total_produced' in msg && typeof msg.total_produced === 'number') {
                    totalProducedRef.current = msg.total_produced!
                    setDetails(`Chunks prepared: ${msg.total_produced}`)
                    updatePercent()
                  }
                  break
                }
                case 'embed': {
                  setStatus('Embedding…')
                  setPhase('Embedding…')
                  if ('count' in msg && typeof msg.count === 'number') {
                    setEmbedded(prev => prev + msg.count)
                  }
                  break
                }
                case 'insert': {
                  setStatus('Inserting…')
                  setPhase('Inserting…')
                  if ('count' in msg && typeof msg.count === 'number') {
                    setInserted(prev => prev + msg.count)
                  }
                  break
                }
                case 'hb': {
                  // heartbeat—show we’re alive during long steps
                  setPhase(prev => prev || 'Working…')
                  break
                }
              }
              continue
            }
          } catch {
            // ignore non-JSON lines
          }
        }
      }
    }

    // drain any trailing event
    if (buffer.trim()) {
      try {
        const msg = JSON.parse(buffer.replace(/^data:\s*/, '')) as SseMsg
        if ('status' in msg && msg.status === 'complete') {
          setStatus('✅ Ingestion complete')
          setPhase('')
          setPercent(100)
        }
      } catch { /* ignore */ }
    }
  }

  // ---------- main submit ----------
  const submit = async () => {
    if (!file && !url.trim()) {
      setStatus('Please choose a file or provide a URL.')
      return
    }

    // reset UI
    setStatus('Starting…')
    setPhase('')
    setDetails('')
    setPercent(0)
    setUploadPercent(0)
    setProduced(0)
    setEmbedded(0)
    setInserted(0)
    totalProducedRef.current = 0
    setLoading(true)

    const controller = new AbortController()
    sseAbortRef.current = controller

    try {
      let csvUrl = url.trim()

      if (file) {
        // 1) presign
        setStatus('Getting upload URL…')
        setPhase('Presigning S3 URL')
        const ext = (file.name.split('.').pop() || 'csv').toLowerCase()
        const { put_url, get_url } = await getPresign(ext)

        // 2) upload with progress
        setStatus('Uploading to S3…')
        setPhase('Uploading file…')
        setUploadPercent(0)
        await uploadToS3(put_url, file, contentTypeForExt(ext), (p) => setUploadPercent(p))

        // 3) kick off ingest with presigned GET url
        csvUrl = get_url
        setStatus('Starting ingest…')
        setPhase('Parsing CSV')
      }

      await startIngest(csvUrl, controller)
    } catch (e: any) {
      if (e?.name === 'AbortError') {
        setStatus('Cancelled.')
      } else {
        setStatus('❌ Failed')
        setPhase('Error')
        setDetails(e?.message ?? String(e))
      }
    } finally {
      setLoading(false)
      sseAbortRef.current = null
      uploadXhrRef.current = null
    }
  }

  const cancelAll = () => {
    // abort SSE or upload (whichever is active)
    try { uploadXhrRef.current?.abort() } catch {}
    sseAbortRef.current?.abort()
  }

  return (
    <div className="max-w-xl space-y-5">
      <h2 className="text-xl font-semibold">Ingest data</h2>

      <div className="space-y-3">
        <label className="block text-sm font-medium">Upload CSV or ZIP</label>
        <Input
          className="hover:cursor-pointer"
          type="file"
          accept=".csv,.zip"
          onChange={e => setFile(e.target.files?.[0] ?? null)}
        />
        <div className="text-center text-xs text-muted-foreground">— or —</div>
        <input
          className="w-full border rounded px-3 py-2"
          placeholder="https://example.com/data.csv"
          value={url}
          onChange={e => setUrl(e.target.value)}
        />
      </div>

      <div className="flex gap-3">
        <Button onClick={submit} disabled={loading}>
          {loading ? 'Ingesting…' : 'Ingest'}
        </Button>
        {loading && (
          <Button type="button" variant="secondary" onClick={cancelAll}>
            Cancel
          </Button>
        )}
      </div>

      {/* Upload Progress (only visible for file path) */}
      {file && loading && (
        <div className="space-y-1">
          <div className="text-xs text-muted-foreground">Upload: {uploadPercent}%</div>
          <div className="h-1 w-full bg-gray-200 rounded">
            <div className="h-1 bg-blue-400 rounded transition-all" style={{ width: `${uploadPercent}%` }} />
          </div>
        </div>
      )}

      {/* Ingest Steps + Progress */}
      <div className="mt-2 space-y-2">
        <div className="h-2 w-full bg-gray-200 rounded">
          <div
            className="h-2 bg-blue-600 rounded transition-all"
            style={{ width: `${percent}%` }}
          />
        </div>

        <div className="text-sm">
          <div className="flex items-center gap-2">
            {loading && <Loader2 className="h-4 w-4 animate-spin text-blue-600" />}
            <div className="font-medium">{status || 'Idle'}</div>
          </div>

          {phase && <div className="text-muted-foreground">{phase}</div>}

          {details && (
            <div className="text-xs text-muted-foreground mt-1 break-words">
              {details}
            </div>
          )}

          <div className="text-xs text-muted-foreground mt-1">
            Produced: {produced} • Embedded: {embedded} • Inserted: {inserted}
            {totalProducedRef.current > 0 && ` • Total: ${totalProducedRef.current}`}
          </div>
        </div>
      </div>
    </div>
  )
}
