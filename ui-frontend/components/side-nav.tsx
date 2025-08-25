'use client'

import Link from 'next/link'
import { Scroll, Upload, User, X } from 'lucide-react'
import { usePathname } from 'next/navigation'
import { cn } from '@/lib/utils'
import { Logo } from '@/components/Logo'

type SideNavProps = {
  className?: string
  onNavigate?: () => void
  showClose?: boolean
}

const links = [
  { href: '/dashboard/ingest', label: 'Ingest', icon: Upload },
  { href: '/dashboard/chat', label: 'Chat', icon: Scroll },
  { href: '/dashboard/account', label: 'Account', icon: User },
]

export function SideNav({ className, onNavigate, showClose }: SideNavProps) {
  const path = usePathname()

  return (
    <aside
      className={cn(
        'w-64 max-w-[80vw] border-r bg-white dark:bg-zinc-950 h-full flex flex-col',
        className
      )}
      aria-label="Sidebar"
    >
      <div className="flex items-center justify-between px-6 py-6">
        <div className="w-[140px]">
          <Logo />
        </div>
        {showClose && (
          <button
            aria-label="Close menu"
            onClick={onNavigate}
            className="p-2 rounded hover:bg-gray-100 dark:hover:bg-zinc-900"
          >
            <X size={20} />
          </button>
        )}
      </div>

      <nav className="mt-2 flex flex-col gap-1">
        {links.map(({ href, label, icon: Icon }) => {
          const active = path.startsWith(href)
          return (
            <Link
              key={href}
              href={href}
              onClick={onNavigate}
              className={cn(
                'flex items-center gap-3 rounded-lg px-4 py-2 mx-2 text-sm transition',
                active ? 'bg-gray-200 text-gray-900' : 'hover:bg-muted'
              )}
            >
              <Icon size={18} /> {label}
            </Link>
          )
        })}
      </nav>
    </aside>
  )
}
