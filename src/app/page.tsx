import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export const runtime = 'edge'

export default async function Page() {
  const supabase = createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (user) {
    redirect('/dashboard')
  }

  redirect('/login')
}
