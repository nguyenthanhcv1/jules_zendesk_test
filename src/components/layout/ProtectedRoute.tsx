'use client'

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useAuth } from '@/modules/auth/hooks/useAuth'

interface ProtectedRouteProps {
  children: React.ReactNode
}

export function ProtectedRoute({ children }: ProtectedRouteProps) {
  const { user, loading } = useAuth()
  const router = useRouter()

  useEffect(() => {
    if (!loading && !user) {
      router.replace('/login')
    }
  }, [user, loading, router])

  if (loading) {
    return (
      <div className="flex flex-col space-y-4 p-8 w-full max-w-4xl mx-auto h-screen justify-center">
        <div className="space-y-4">
          <div className="h-8 bg-slate-200 rounded animate-pulse w-1/4"></div>
          <div className="space-y-2">
            <div className="h-4 bg-slate-200 rounded animate-pulse w-full"></div>
            <div className="h-4 bg-slate-200 rounded animate-pulse w-full"></div>
            <div className="h-4 bg-slate-200 rounded animate-pulse w-3/4"></div>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mt-8">
            <div className="h-32 bg-slate-200 rounded animate-pulse"></div>
            <div className="h-32 bg-slate-200 rounded animate-pulse"></div>
            <div className="h-32 bg-slate-200 rounded animate-pulse"></div>
          </div>
        </div>
      </div>
    )
  }

  if (!user) {
    return null
  }

  return <>{children}</>
}
