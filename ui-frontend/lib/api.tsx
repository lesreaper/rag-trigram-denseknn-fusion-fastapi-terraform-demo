export async function chatStream(
  q: string,
  tenant_id: string,
  onChunk: (chunk: string) => void
) {
  if (!q?.trim() || !tenant_id?.trim()) {
    throw new Error('Missing q or tenant_id on client')
  }

  const resp = await fetch('/proxy/chat/stream', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ q, tenant_id }),
  })

  if (!resp.ok || !resp.body) {
    const errText = await resp.text().catch(() => '')
    throw new Error(errText || `chat stream failed (${resp.status})`)
  }

  const reader = resp.body.getReader()
  const decoder = new TextDecoder()
  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    onChunk(decoder.decode(value))
  }
}

export async function ingestStream(
  form: FormData,
  onEvent: (evt: { status?: string; progress?: number; total?: number }) => void
) {
  const resp = await fetch('/api/ingest/stream', { method: 'POST', body: form })
  if (!resp.ok || !resp.body) throw new Error('Ingest stream failed')

  const reader = resp.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''

  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    buffer += decoder.decode(value, { stream: true })

    // handle SSE-style "data: {...}\n\n"
    let idx
    while ((idx = buffer.indexOf('\n\n')) !== -1) {
      const chunk = buffer.slice(0, idx)
      buffer = buffer.slice(idx + 2)
      const line = chunk.split('\n').find(l => l.startsWith('data:')) || chunk
      const jsonStr = line.replace(/^data:\s*/, '')
      try {
        const evt = JSON.parse(jsonStr)
        onEvent(evt)
      } catch {
        // ignore partial/non-JSON
      }
    }
  }
}
