import React, { createContext, useContext, useState, useCallback, ReactNode } from 'react';
import { User, Portfolio, Notification, GiftReveal } from '../types';
import { mockPositions, mockNotifications, mockStocks, mockGiftReveal, mockEducationModules } from '../data/mockData';

interface AppState {
  isOnboarded: boolean;
  isAuthenticated: boolean;
  user: User | null;
  portfolio: Portfolio;
  notifications: Notification[];
  unreadCount: number;
  giftReveal: GiftReveal;
  completedModules: string[];
  activationCode: string | null;
}

interface AppContextType extends AppState {
  completeOnboarding: () => void;
  setUser: (user: User) => void;
  login: () => void;
  logout: () => void;
  markNotificationRead: (id: string) => void;
  deleteNotification: (id: string) => void;
  completeModule: (id: string) => void;
  setActivationCode: (code: string) => void;
}

const defaultPortfolio: Portfolio = {
  totalValue: 1294.53,
  totalGain: 93.78,
  totalGainPercent: 7.81,
  positions: mockPositions,
};

const AppContext = createContext<AppContextType>({} as AppContextType);

export const AppProvider = ({ children }: { children: ReactNode }) => {
  const [isOnboarded, setIsOnboarded] = useState(false);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [user, setUserState] = useState<User | null>(null);
  const [portfolio] = useState<Portfolio>(defaultPortfolio);
  const [notifications, setNotifications] = useState<Notification[]>(mockNotifications);
  const [completedModules, setCompletedModules] = useState<string[]>(['1', '2', '3']);
  const [activationCode, setActivationCodeState] = useState<string | null>(null);

  const unreadCount = notifications.filter(n => !n.read).length;

  const completeOnboarding = useCallback(() => setIsOnboarded(true), []);
  const setUser = useCallback((u: User) => { setUserState(u); setIsAuthenticated(true); }, []);
  const login = useCallback(() => setIsAuthenticated(true), []);
  const logout = useCallback(() => { setIsAuthenticated(false); setIsOnboarded(false); setUserState(null); }, []);

  const markNotificationRead = useCallback((id: string) => {
    setNotifications(prev => prev.map(n => n.id === id ? { ...n, read: true } : n));
  }, []);

  const deleteNotification = useCallback((id: string) => {
    setNotifications(prev => prev.filter(n => n.id !== id));
  }, []);

  const completeModule = useCallback((id: string) => {
    setCompletedModules(prev => prev.includes(id) ? prev : [...prev, id]);
  }, []);

  const setActivationCode = useCallback((code: string) => {
    setActivationCodeState(code);
  }, []);

  return (
    <AppContext.Provider value={{
      isOnboarded, isAuthenticated, user, portfolio, notifications, unreadCount,
      giftReveal: mockGiftReveal, completedModules, activationCode,
      completeOnboarding, setUser, login, logout,
      markNotificationRead, deleteNotification, completeModule, setActivationCode,
    }}>
      {children}
    </AppContext.Provider>
  );
};

export const useApp = () => useContext(AppContext);
