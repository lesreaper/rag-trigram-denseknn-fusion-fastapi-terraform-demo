'use client'
import { useState } from 'react'
import { chatStream } from '@/lib/api'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import { Mic } from 'lucide-react'

export default function ChatPage() {
  const [q, setQ] = useState('')
  const [ans, setAns] = useState('')
  const [loading, setLoading] = useState(false)
  const tenant = 'demo' // or from user/org context

  const ask = async () => {
    if (!q.trim()) return
    setAns('')
    setLoading(true)
    try {
      await chatStream(q, tenant, (chunk) => {
        setAns((prev) => prev + chunk)
      })
    } catch (e: any) {
      setAns(`Error: ${e.message ?? '…'}`)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="max-w-xl space-y-4">
      <h2 className="text-xl font-semibold">Chat</h2>
      <Textarea placeholder="Ask a question…" value={q} onChange={e => setQ(e.target.value)} />
      <div className='flex items-center relative'>
<Button onClick={ask} disabled={loading}>
        {loading ? 'Streaming…' : 'Send'}
      </Button>
        <Mic
          className="text-gray-500 cursor-pointer mx-4"
          size={20}
          // no click handler yet — purely decorative
        />
      
      </div>
      {ans && <div className="border rounded p-3 whitespace-pre-wrap mt-2 min-h-[4rem]">{ans}</div>}
    </div>
  )
}
