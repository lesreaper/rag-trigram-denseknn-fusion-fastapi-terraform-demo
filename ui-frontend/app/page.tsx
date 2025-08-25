import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'

export default async function Home() {
  const cookieStore = await cookies()
  const isAuth = cookieStore.get('auth')?.value === 'true'
  redirect(isAuth ? '/dashboard' : '/login')
}
