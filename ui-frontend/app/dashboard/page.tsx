'use client'

import { useRouter } from 'next/navigation'
import { Button } from '@/components/ui/button'

export default function DashboardPage() {
  const router = useRouter()

  return (
    <div className="max-w-2xl mx-auto space-y-8 text-center pt-20">
      <div>
        <h1 className="text-4xl font-semibold tracking-tight">Welcome to Kizen 👋</h1>
        <p className="mt-2 text-muted-foreground text-lg">
          Your personal document-powered AI workspace.
        </p>
      </div>

      <div className="grid gap-6">
        <div>
          <h2 className="text-xl font-medium mb-2">First time here?</h2>
          <Button
            onClick={() => router.push('/dashboard/ingest')}
            className="w-full sm:w-auto hover:cursor-pointer"
          >
            Ingest Documents
          </Button>
        </div>

        <div>
          <h2 className="text-xl font-medium mb-2">Already uploaded content?</h2>
          <Button
            variant="secondary"
            onClick={() => router.push('/dashboard/chat')}
            className="w-full sm:w-auto hover:cursor-pointer hover:bg-gray-300"
          >
            Go to Chat
          </Button>
        </div>
      </div>

      <p className="text-sm text-gray-500 mt-12">
        Need help? Reach out to the team or check the docs.
      </p>
    </div>
  )
}
