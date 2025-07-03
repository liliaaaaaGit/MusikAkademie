import { useState } from 'react';
import { NavLink, useNavigate, Link } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Sheet, SheetContent, SheetTrigger, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { LogOut, Users, GraduationCap, FileText, Clock, Bell, Menu } from 'lucide-react';
import { cn } from '@/lib/utils';

export function MobileNavigation() {
  const { profile, signOut } = useAuth();
  const [isOpen, setIsOpen] = useState(false);
  const navigate = useNavigate();

  const handleSignOut = async () => {
    await signOut();
    setIsOpen(false);
  };

  const handleNavigation = (path: string) => {
    navigate(path);
    setIsOpen(false);
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
    <div className="bg-white border-b border-gray-200 px-4 py-3">
      <div className="flex items-center justify-between">
        {/* Logo */}
        <div className="flex items-center space-x-3">
          <img 
            src="/logo.png" 
            alt="MAM Logo" 
            className="h-10 w-auto"
          />
          <div className="flex flex-col">
            <h1 className="text-lg font-bold text-gray-900 leading-tight">
              MAM
            </h1>
            <span className="text-xs text-gray-600">
              Verwaltungssystem
            </span>
          </div>
        </div>

        {/* Hamburger Menu */}
        <Sheet open={isOpen} onOpenChange={setIsOpen}>
          <SheetTrigger asChild>
            <Button 
              variant="ghost" 
              size="sm"
              className="p-2 hover:bg-gray-100"
            >
              <Menu className="h-6 w-6 text-gray-700" />
            </Button>
          </SheetTrigger>
          <SheetContent side="right" className="w-80 p-0">
            <div className="flex flex-col h-full">
              {/* Header */}
              <SheetHeader className="p-6 border-b border-gray-200">
                <div className="flex items-center justify-between">
                  <SheetTitle className="text-lg font-semibold text-gray-900">
                    Navigation
                  </SheetTitle>
                </div>
              </SheetHeader>

              {/* User Profile Section */}
              <div className="p-6 border-b border-gray-200">
                <div className="flex items-center space-x-4">
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
              </div>

              {/* Navigation Items */}
              <nav className="flex-1 px-6 py-4 space-y-2 overflow-y-auto">
                {navigationItems.map((item) => {
                  const Icon = item.icon;
                  return (
                    <NavLink
                      key={item.name}
                      to={item.href}
                      onClick={() => handleNavigation(item.href)}
                      className={({ isActive }) =>
                        cn(
                          "flex items-center space-x-4 px-4 py-3 text-base font-medium rounded-lg transition-colors w-full",
                          isActive
                            ? "bg-brand-primary text-white"
                            : "text-gray-700 hover:bg-gray-100 hover:text-gray-700"
                        )
                      }
                    >
                      <Icon className="h-5 w-5" />
                      <span>{item.name}</span>
                    </NavLink>
                  );
                })}
              </nav>

              {/* Sign Out Button and Privacy Link */}
              <div className="p-6 border-t border-gray-200">
                <Button
                  variant="outline"
                  size="default"
                  onClick={handleSignOut}
                  className="w-full justify-start bg-brand-gray hover:bg-brand-gray/80 text-gray-700 border-brand-gray h-11 focus:ring-brand-primary mb-4"
                >
                  <LogOut className="h-5 w-5 mr-3" />
                  Abmelden
                </Button>
                
                {/* Privacy Policy Link */}
                <div className="text-center">
                  <Link 
                    to="/datenschutz" 
                    onClick={() => setIsOpen(false)}
                    className="text-xs text-gray-500 underline hover:text-brand-primary hover:no-underline transition-colors"
                  >
                    Datenschutzerklärung
                  </Link>
                </div>
              </div>
            </div>
          </SheetContent>
        </Sheet>
      </div>
    </div>
  );
}