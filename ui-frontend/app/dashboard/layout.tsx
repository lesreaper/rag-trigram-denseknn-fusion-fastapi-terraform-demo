'use client'

import { useState } from 'react'
import { SideNav } from '@/components/side-nav'
import { Menu } from 'lucide-react'
import { Logo } from '@/components/Logo'
import '@/app/globals.css'

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const [open, setOpen] = useState(false)

  return (
    <div className="min-h-screen w-full">
      {/* Top bar (mobile only) */}
      <header className="md:hidden sticky top-0 z-40 flex items-center justify-between px-4 py-3 border-b bg-white dark:bg-zinc-950">
        <div className="flex items-center justify-between w-full">
          <button
            aria-label="Open menu"
            onClick={() => setOpen(true)}
            className="p-2 rounded hover:bg-gray-100 dark:hover:bg-zinc-900"
          >
            <Menu size={22} />
          </button>
          <div className="w-[80px]">
            <Logo /> {/* This will render your small Kizen logo */}
          </div>
        </div>
        <div className="w-[22px]" /> {/* Spacer so title stays centered if you want */}
      </header>

      <div className="flex">
        {/* Desktop sidebar */}
        <div className="hidden md:block sticky top-0 h-screen">
          <SideNav />
        </div>

        {/* Mobile drawer */}
        {open && (
          <>
            {/* overlay */}
            <div
              className="fixed inset-0 z-40 bg-black/40"
              onClick={() => setOpen(false)}
              aria-hidden="true"
            />
            {/* drawer panel */}
            <div className="fixed z-50 inset-y-0 left-0">
              <SideNav showClose onNavigate={() => setOpen(false)} />
            </div>
          </>
        )}

        {/* Main content */}
        <main className="flex-1 bg-muted/40 p-4 md:p-6 overflow-y-auto w-full">
          {children}
        </main>
      </div>
    </div>
  )
}
