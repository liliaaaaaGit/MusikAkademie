import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { LoginForm } from '@/components/LoginForm';
import { Layout } from '@/components/Layout';
import { StudentsTab } from '@/components/tabs/StudentsTab';
import { TeachersTab } from '@/components/tabs/TeachersTab';
import { ContractsTab } from '@/components/tabs/ContractsTab';
import { TrialAppointmentsTab } from '@/components/tabs/TrialAppointmentsTab';
import { NotificationsTab } from '@/components/tabs/NotificationsTab';
import DatenschutzPage from '@/components/DatenschutzPage';
import { PrivacyPolicyPage } from '@/components/PrivacyPolicyPage';
import ImpressumPage from '@/components/ImpressumPage';
import { useAuth } from '@/hooks/useAuth';
import { Toaster } from 'sonner';
import RegisterPage from '@/components/RegisterPage';

function App() {
  const { user, loading, configError } = useAuth();

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
      </div>
    );
  }

  if (configError) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="max-w-md mx-auto text-center p-6 bg-white rounded-lg shadow-lg">
          <div className="text-red-500 text-6xl mb-4">⚠️</div>
          <h1 className="text-2xl font-bold text-gray-900 mb-4">Configuration Required</h1>
          <p className="text-gray-600 mb-6">
            This app requires Supabase configuration to work properly. Please set up your environment variables:
          </p>
          <div className="bg-gray-100 p-4 rounded-lg text-left text-sm font-mono mb-6">
            <div className="text-green-600"># Create a .env file in your project root with:</div>
            <div>VITE_SUPABASE_URL=your_supabase_url</div>
            <div>VITE_SUPABASE_ANON_KEY=your_supabase_anon_key</div>
          </div>
          <p className="text-sm text-gray-500">
            Get these values from your{' '}
            <a href="https://supabase.com" target="_blank" rel="noopener noreferrer" className="text-blue-500 hover:underline">
              Supabase project dashboard
            </a>
          </p>
        </div>
      </div>
    );
  }

  return (
    <Router>
      <Routes>
        <Route 
          path="/login" 
          element={!user ? <LoginForm /> : <Navigate to="/students" replace />} 
        />
        <Route 
          path="/datenschutz" 
          element={<DatenschutzPage />} 
        />
        <Route 
          path="/privacy-policy" 
          element={<PrivacyPolicyPage />} 
        />
        <Route 
          path="/impressum" 
          element={<ImpressumPage />} 
        />
        <Route 
          path="/" 
          element={user ? <Layout><Navigate to="/students" replace /></Layout> : <Navigate to="/login" replace />} 
        />
        <Route 
          path="/students" 
          element={user ? <Layout><StudentsTab /></Layout> : <Navigate to="/login" replace />} 
        />
        <Route 
          path="/teachers" 
          element={user ? <Layout><TeachersTab /></Layout> : <Navigate to="/login" replace />} 
        />
        <Route 
          path="/contracts" 
          element={user ? <Layout><ContractsTab /></Layout> : <Navigate to="/login" replace />} 
        />
        <Route 
          path="/trials" 
          element={user ? <Layout><TrialAppointmentsTab /></Layout> : <Navigate to="/login" replace />} 
        />
        <Route 
          path="/inbox" 
          element={user ? <Layout><NotificationsTab /></Layout> : <Navigate to="/login" replace />} 
        />
        <Route 
          path="/register" 
          element={!user ? <RegisterPage /> : <Navigate to="/students" replace />} 
        />
        <Route path="*" element={<Navigate to="/students" replace />} />
      </Routes>
      <Toaster position="top-right" />
    </Router>
  );
}

export default App;