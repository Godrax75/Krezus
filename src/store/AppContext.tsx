import React, { createContext, useContext, useState, useCallback, useEffect, ReactNode } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { User, Portfolio, Notification, GiftReveal, Stock } from '../types';
import { mockPositions, mockNotifications, mockGiftReveal, mockStocks } from '../data/mockData';
import {
  computePortfolio,
  getStocksSnapshot,
  invalidateMarketData,
  isLiveDataEnabled,
} from '../services';

interface AppState {
  isLoading: boolean;
  isOnboarded: boolean;
  isAuthenticated: boolean;
  user: User | null;
  /** Fiches valeurs, clés historiques (`AAPL`, `MSFT`, `LVMH`). */
  stocks: Record<string, Stock>;
  portfolio: Portfolio;
  /** Un rafraîchissement des cours est en cours. */
  isMarketDataLoading: boolean;
  /** Les cours affichés viennent du fournisseur, pas des données de démo. */
  isLiveMarketData: boolean;
  /** Horodatage du dernier rafraîchissement réussi. */
  marketDataUpdatedAt: number | null;
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
  /** Effacement définitif du compte et de toutes ses données locales. */
  deleteAccount: () => Promise<void>;
  refreshMarketData: (force?: boolean) => Promise<void>;
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

// Les totaux sont dérivés des lignes et des cours : plus de valeurs en dur qui
// se désynchronisent dès que les prix bougent.
const defaultPortfolio: Portfolio = computePortfolio(mockPositions, mockStocks);

const AppContext = createContext<AppContextType>({} as AppContextType);

export const AppProvider = ({ children }: { children: ReactNode }) => {
  const [isLoading, setIsLoading] = useState(true);
  const [isOnboarded, setIsOnboarded] = useState(false);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [user, setUserState] = useState<User | null>(null);
  const [stocks, setStocks] = useState<Record<string, Stock>>(mockStocks);
  const [portfolio, setPortfolio] = useState<Portfolio>(defaultPortfolio);
  const [isMarketDataLoading, setIsMarketDataLoading] = useState(false);
  const [isLiveMarketData, setIsLiveMarketData] = useState(false);
  const [marketDataUpdatedAt, setMarketDataUpdatedAt] = useState<number | null>(null);
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

  /**
   * Rafraîchit les cours en lecture seule.
   * Ne rejette jamais : sans clé API ou sans réseau, on garde simplement les
   * dernières valeurs connues (données de démo au premier lancement).
   */
  const refreshMarketData = useCallback(async (force = false) => {
    if (!isLiveDataEnabled) return;

    setIsMarketDataLoading(true);
    try {
      if (force) invalidateMarketData();
      const stockIds = mockPositions.map((position) => position.stockId);
      const { data, isLive } = await getStocksSnapshot(stockIds, force);
      setStocks(data);
      setPortfolio(computePortfolio(mockPositions, data));
      setIsLiveMarketData(isLive);
      if (isLive) setMarketDataUpdatedAt(Date.now());
    } finally {
      setIsMarketDataLoading(false);
    }
  }, []);

  // Premier chargement des cours au démarrage.
  useEffect(() => {
    refreshMarketData();
  }, [refreshMarketData]);

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

  /**
   * Suppression de compte — exigée par la règle 5.1.1(v) de l'App Store pour
   * toute app permettant d'en créer un. Contrairement à la déconnexion, tout
   * est effacé : profil, progression et notifications.
   */
  const deleteAccount = useCallback(async () => {
    setIsAuthenticated(false);
    setIsOnboarded(false);
    setUserState(null);
    setActivationCodeState(null);
    setCompletedModules([]);
    setNotifications(mockNotifications);
    await AsyncStorage.multiRemove(Object.values(STORAGE_KEYS));
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
      isLoading, isOnboarded, isAuthenticated, user, stocks, portfolio,
      isMarketDataLoading, isLiveMarketData, marketDataUpdatedAt,
      notifications, unreadCount,
      giftReveal: mockGiftReveal, completedModules, activationCode,
      completeOnboarding, setUser, login, logout, deleteAccount, refreshMarketData,
      markNotificationRead, deleteNotification, completeModule, setActivationCode,
    }}>
      {children}
    </AppContext.Provider>
  );
};

export const useApp = () => useContext(AppContext);
