import { NavLink, Link } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { LogOut, Users, GraduationCap, FileText, Clock, Bell } from 'lucide-react';
import { cn } from '@/lib/utils';

export function Sidebar() {
  const { profile, signOut } = useAuth();

  const handleSignOut = async () => {
    await signOut();
  };

  const getInitials = (name: string) => {
    return name
      .split(' ')
      .map(part => part[0])
      .join('')
      .toUpperCase()
      .slice(0, 2);
  };

  const navigationItems = [
    {
      name: 'Schüler',
      href: '/students',
      icon: Users,
    },
    ...(profile?.role === 'admin' ? [{
      name: 'Lehrer',
      href: '/teachers',
      icon: GraduationCap,
    }] : []),
    {
      name: 'Verträge',
      href: '/contracts',
      icon: FileText,
    },
    {
      name: 'Probestunden',
      href: '/trials',
      icon: Clock,
    },
    {
      name: 'Postfach',
      href: '/inbox',
      icon: Bell,
    },
  ];

  return (
    <div className="flex h-full w-80 flex-col bg-white border-r border-gray-200 flex-shrink-0">
      {/* Logo and Title - Centered */}
      <div className="flex flex-col items-center justify-center p-8 border-b border-gray-200">
        <img 
          src="/logo.png" 
          alt="MAM Logo" 
          className="h-16 w-auto mb-3"
        />
        <span className="text-sm text-gray-500 font-medium">
          Verwaltung
        </span>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-6 py-8 space-y-3 overflow-y-auto">
        {navigationItems.map((item) => {
          const Icon = item.icon;
          return (
            <NavLink
              key={item.name}
              to={item.href}
              className={({ isActive }) =>
                cn(
                  "flex items-center space-x-4 px-5 py-4 text-base font-medium rounded-lg transition-colors",
                  isActive
                    ? "bg-brand-primary text-white hover:bg-brand-primary hover:text-white"
                    : "text-gray-700 hover:bg-gray-100 hover:text-gray-700"
                )
              }
            >
              <Icon className="h-6 w-6" />
              <span>{item.name}</span>
            </NavLink>
          );
        })}
      </nav>

      {/* User Profile */}
      <div className="border-t border-gray-200 p-6 flex-shrink-0">
        <div className="flex items-center space-x-4 mb-6">
          <Avatar className="h-12 w-12">
            <AvatarFallback className="bg-brand-primary/10 text-brand-primary text-base">
              {getInitials(profile?.full_name || '')}
            </AvatarFallback>
          </Avatar>
          <div className="flex-1 min-w-0">
            <p className="text-base font-medium text-gray-900 truncate">
              {profile?.full_name}
            </p>
            {profile?.role === 'admin' && (
              <span className="inline-flex items-center px-2.5 py-1 rounded text-xs font-medium bg-brand-primary text-white mt-1">
                Administrator
              </span>
            )}
          </div>
        </div>
        <Button
          variant="outline"
          size="default"
          onClick={handleSignOut}
          className="w-full justify-start bg-brand-gray hover:bg-brand-gray/80 text-gray-700 border-brand-gray h-11 mb-4"
        >
          <LogOut className="h-5 w-5 mr-3" />
          Abmelden
        </Button>
        
        {/* Privacy Policy Link */}
        <div className="text-center">
          <Link 
            to="/datenschutz" 
            className="text-xs text-gray-500 underline hover:text-brand-primary hover:no-underline transition-colors"
          >
            Datenschutzerklärung
          </Link>
          <span className="mx-2 text-gray-300">|</span>
          <Link 
            to="/impressum" 
            className="text-xs text-gray-500 underline hover:text-brand-primary hover:no-underline transition-colors"
          >
            Impressum
          </Link>
        </div>
      </div>
    </div>
  );
}