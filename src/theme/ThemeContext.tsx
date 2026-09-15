import React, { createContext, useContext, useState, useCallback, ReactNode } from 'react';
import { Colors, ThemeColors } from './colors';

type ThemeMode = 'dark' | 'light' | 'auto';

interface ThemeContextType {
  mode: ThemeMode;
  colors: ThemeColors;
  isDark: boolean;
  setMode: (mode: ThemeMode) => void;
}

const ThemeContext = createContext<ThemeContextType>({
  mode: 'dark',
  colors: Colors.dark,
  isDark: true,
  setMode: () => {},
});

export const ThemeProvider = ({ children }: { children: ReactNode }) => {
  const [mode, setModeState] = useState<ThemeMode>('dark');

  const isDark = mode === 'dark' || mode === 'auto';
  const colors = isDark ? Colors.dark : Colors.light;

  const setMode = useCallback((newMode: ThemeMode) => {
    setModeState(newMode);
  }, []);

  return (
    <ThemeContext.Provider value={{ mode, colors, isDark, setMode }}>
      {children}
    </ThemeContext.Provider>
  );
};

export const useTheme = () => useContext(ThemeContext);
