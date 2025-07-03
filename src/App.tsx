import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { LoginForm } from '@/components/LoginForm';
import { Layout } from '@/components/Layout';
import { StudentsTab } from '@/components/tabs/StudentsTab';
import { TeachersTab } from '@/components/tabs/TeachersTab';
import { ContractsTab } from '@/components/tabs/ContractsTab';
import { TrialAppointmentsTab } from '@/components/tabs/TrialAppointmentsTab';
import { NotificationsTab } from '@/components/tabs/NotificationsTab';
import { DatenschutzPage } from '@/components/DatenschutzPage';
import { useAuth } from '@/hooks/useAuth';
import { Toaster } from 'sonner';

function App() {
  const { user, loading } = useAuth();

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
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
        <Route path="*" element={<Navigate to="/students" replace />} />
      </Routes>
      <Toaster position="top-right" />
    </Router>
  );
}

export default App;