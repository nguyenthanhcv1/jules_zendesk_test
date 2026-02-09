'use client'

import { ProtectedRoute } from '@/components/layout/ProtectedRoute'
import { useAuth } from '@/modules/auth/hooks/useAuth'
import { Button } from '@/components/ui/button'

export default function DashboardPage() {
  const { user, signOut } = useAuth()

  return (
    <ProtectedRoute>
      <div className="min-h-screen bg-slate-50 p-8">
        <div className="max-w-4xl mx-auto">
          <header className="flex justify-between items-center mb-8">
            <div>
              <h1 className="text-3xl font-bold text-slate-900">Dashboard</h1>
              <p className="text-slate-500">Welcome back, {user?.email}</p>
            </div>
            <Button variant="outline" onClick={() => signOut()}>
              Sign Out
            </Button>
          </header>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div className="bg-white p-6 rounded-lg shadow-sm border border-slate-200">
              <h2 className="font-semibold text-slate-700 mb-2">Total Evaluations</h2>
              <p className="text-4xl font-bold text-slate-900">24</p>
            </div>
            <div className="bg-white p-6 rounded-lg shadow-sm border border-slate-200">
              <h2 className="font-semibold text-slate-700 mb-2">Pending Review</h2>
              <p className="text-4xl font-bold text-slate-900">5</p>
            </div>
            <div className="bg-white p-6 rounded-lg shadow-sm border border-slate-200">
              <h2 className="font-semibold text-slate-700 mb-2">Average Score</h2>
              <p className="text-4xl font-bold text-slate-900">8.5</p>
            </div>
          </div>
        </div>
      </div>
    </ProtectedRoute>
  )
}
