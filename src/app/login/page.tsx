'use client'

export const runtime = 'edge'

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useAuth } from '@/modules/auth/hooks/useAuth'
import { LoginForm } from '@/modules/auth/components/LoginForm'

export default function LoginPage() {
  const { user, loading } = useAuth()
  const router = useRouter()

  useEffect(() => {
    if (!loading && user) {
      router.replace('/dashboard')
    }
  }, [user, loading, router])

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-slate-50">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-slate-900"></div>
      </div>
    )
  }

  // If user is already logged in, the useEffect will handle redirection.
  // We can also return null or a loading state here if user is present to avoid flicker.
  if (user) {
    return null
  }

  return <LoginForm />
}
