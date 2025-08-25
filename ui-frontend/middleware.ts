// middleware.ts
import { NextRequest, NextResponse } from 'next/server'

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl
  const isAuth = request.cookies.get('auth')?.value === 'true'

  // public assets and routes
  const isPublic =
    pathname === '/login' ||
    pathname.startsWith('/api') ||
    pathname.startsWith('/_next') ||
    pathname.startsWith('/favicon') ||
    pathname.startsWith('/fonts') ||
    pathname.startsWith('/assets')

  // Only guard /dashboard/* (and /login)
  if (!isAuth && pathname.startsWith('/dashboard')) {
    return NextResponse.redirect(new URL('/login', request.url))
  }
  if (isAuth && pathname === '/login') {
    return NextResponse.redirect(new URL('/dashboard', request.url))
  }

  return NextResponse.next()
}

export const config = {
  // match everything except files with extensions
  matcher: ['/((?!.*\\.).*)'],
}
