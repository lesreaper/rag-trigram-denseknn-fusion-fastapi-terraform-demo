'use client'

import { useRouter } from 'next/navigation'
import { Button } from '@/components/ui/button'
export default function AccountPage(){
  const router = useRouter()

  const handleLogout = async () => {
    await fetch('/proxy/logout', { method: 'POST' })
    router.push('/login')
  }

  return <div className="p-4">
    <Button onClick={handleLogout} className="mt-4">
      Logout
    </Button>
    <p className="text-sm text-gray-500 mt-12">
      Need help? Reach out to the team or check the docs. 
    </p>
  </div>
}