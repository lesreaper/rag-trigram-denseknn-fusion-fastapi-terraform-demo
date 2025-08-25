import { NextRequest, NextResponse } from 'next/server'

export async function POST(req: NextRequest) {
  const { username, password } = await req.json()

  const ok =
    username === (process.env.USERNAME ?? 'demo') &&
    password === (process.env.PASSWORD ?? 'demo')

  if (!ok) {
    return NextResponse.json({ success: false, message: 'Invalid login' }, { status: 401 })
  }

  // Use request scheme to decide Secure
  const isHttps =
    req.nextUrl.protocol === 'https:' ||
    req.headers.get('x-forwarded-proto') === 'https' ||
    process.env.COOKIE_SECURE === 'true' // override if needed

  const res = NextResponse.json({ success: true })
  res.cookies.set('auth', 'true', {
    httpOnly: true,
    secure: isHttps,
    sameSite: 'lax',
    path: '/',
  })
  return res
}
