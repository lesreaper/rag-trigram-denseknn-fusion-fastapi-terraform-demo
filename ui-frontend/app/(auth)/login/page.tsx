'use client'
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { Logo } from '@/components/Logo'
import { Button } from '@/components/ui/button'

export default function LoginPage() {
  const [username, setU] = useState('')
  const [password, setP] = useState('')
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const router = useRouter()

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setErr(null)
    try {
      const r = await fetch('/proxy/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password }),
        credentials: 'include',
      })
      if (!r.ok) {
        const j = await r.json().catch(() => ({}))
        throw new Error(j.message ?? 'Login failed')
      }
      // Cookie set by server; go straight to /dashboard
      router.replace('/dashboard')
    } catch (e: any) {
      setErr(e.message ?? 'Login failed')
    } finally {
      setLoading(false)
    }
  }

  return (
    <form onSubmit={submit} className="bg-white p-8 rounded-xl shadow w-96 flex flex-col gap-4">
      <div className="p-4 mb-6">
        <Logo />
      </div>
      <h1 className="text-2xl font-semibold text-center">Sign in</h1>
      <input className="border rounded px-3 py-2" placeholder="Username" value={username} onChange={e => setU(e.target.value)} />
      <input className="border rounded px-3 py-2" type="password" placeholder="Password" value={password} onChange={e => setP(e.target.value)} />
      <Button disabled={loading} className="rounded bg-black text-white py-2 hover:cursor-pointer">
        {loading ? 'Signing in…' : 'Continue'}
      </Button>
      {err && <p className="text-sm text-red-600">{err}</p>}
    </form>
  )
}
