import React, { createContext, useContext, useState, useCallback, useEffect, ReactNode } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { User, Portfolio, Notification, GiftReveal } from '../types';
import { mockPositions, mockNotifications, mockGiftReveal } from '../data/mockData';

interface AppState {
  isLoading: boolean;
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

const STORAGE_KEYS = {
  IS_ONBOARDED: '@krezus_is_onboarded',
  IS_AUTHENTICATED: '@krezus_is_authenticated',
  USER: '@krezus_user',
  COMPLETED_MODULES: '@krezus_completed_modules',
  NOTIFICATIONS: '@krezus_notifications',
};

const defaultPortfolio: Portfolio = {
  totalValue: 1294.53,
  totalGain: 93.78,
  totalGainPercent: 7.81,
  positions: mockPositions,
};

const AppContext = createContext<AppContextType>({} as AppContextType);

export const AppProvider = ({ children }: { children: ReactNode }) => {
  const [isLoading, setIsLoading] = useState(true);
  const [isOnboarded, setIsOnboarded] = useState(false);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [user, setUserState] = useState<User | null>(null);
  const [portfolio] = useState<Portfolio>(defaultPortfolio);
  const [notifications, setNotifications] = useState<Notification[]>(mockNotifications);
  const [completedModules, setCompletedModules] = useState<string[]>(['1', '2', '3']);
  const [activationCode, setActivationCodeState] = useState<string | null>(null);

  const unreadCount = notifications.filter(n => !n.read).length;

  // Load persisted data on mount
  useEffect(() => {
    const loadPersistedData = async () => {
      try {
        const [onboardedStr, authStr, userStr, modulesStr, notifStr] = await Promise.all([
          AsyncStorage.getItem(STORAGE_KEYS.IS_ONBOARDED),
          AsyncStorage.getItem(STORAGE_KEYS.IS_AUTHENTICATED),
          AsyncStorage.getItem(STORAGE_KEYS.USER),
          AsyncStorage.getItem(STORAGE_KEYS.COMPLETED_MODULES),
          AsyncStorage.getItem(STORAGE_KEYS.NOTIFICATIONS),
        ]);

        if (onboardedStr === 'true') setIsOnboarded(true);
        if (authStr === 'true') setIsAuthenticated(true);
        if (userStr) setUserState(JSON.parse(userStr));
        if (modulesStr) setCompletedModules(JSON.parse(modulesStr));
        if (notifStr) setNotifications(JSON.parse(notifStr));
      } catch {
        // Silently fail — first launch or corrupted data
      } finally {
        setIsLoading(false);
      }
    };
    loadPersistedData();
  }, []);

  const completeOnboarding = useCallback(() => {
    setIsOnboarded(true);
    AsyncStorage.setItem(STORAGE_KEYS.IS_ONBOARDED, 'true');
  }, []);

  const setUser = useCallback((u: User) => {
    setUserState(u);
    setIsAuthenticated(true);
    AsyncStorage.setItem(STORAGE_KEYS.USER, JSON.stringify(u));
    AsyncStorage.setItem(STORAGE_KEYS.IS_AUTHENTICATED, 'true');
  }, []);

  const login = useCallback(() => {
    setIsAuthenticated(true);
    AsyncStorage.setItem(STORAGE_KEYS.IS_AUTHENTICATED, 'true');
  }, []);

  const logout = useCallback(async () => {
    setIsAuthenticated(false);
    setIsOnboarded(false);
    setUserState(null);
    await AsyncStorage.multiRemove([
      STORAGE_KEYS.IS_ONBOARDED,
      STORAGE_KEYS.IS_AUTHENTICATED,
      STORAGE_KEYS.USER,
    ]);
  }, []);

  const markNotificationRead = useCallback((id: string) => {
    setNotifications(prev => {
      const updated = prev.map(n => n.id === id ? { ...n, read: true } : n);
      AsyncStorage.setItem(STORAGE_KEYS.NOTIFICATIONS, JSON.stringify(updated));
      return updated;
    });
  }, []);

  const deleteNotification = useCallback((id: string) => {
    setNotifications(prev => {
      const updated = prev.filter(n => n.id !== id);
      AsyncStorage.setItem(STORAGE_KEYS.NOTIFICATIONS, JSON.stringify(updated));
      return updated;
    });
  }, []);

  const completeModule = useCallback((id: string) => {
    setCompletedModules(prev => {
      if (prev.includes(id)) return prev;
      const updated = [...prev, id];
      AsyncStorage.setItem(STORAGE_KEYS.COMPLETED_MODULES, JSON.stringify(updated));
      return updated;
    });
  }, []);

  const setActivationCode = useCallback((code: string) => {
    setActivationCodeState(code);
  }, []);

  return (
    <AppContext.Provider value={{
      isLoading, isOnboarded, isAuthenticated, user, portfolio, notifications, unreadCount,
      giftReveal: mockGiftReveal, completedModules, activationCode,
      completeOnboarding, setUser, login, logout,
      markNotificationRead, deleteNotification, completeModule, setActivationCode,
    }}>
      {children}
    </AppContext.Provider>
  );
};

export const useApp = () => useContext(AppContext);
