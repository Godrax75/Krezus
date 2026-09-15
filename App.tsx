import React from 'react';
import { StatusBar } from 'expo-status-bar';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { NavigationContainer, LinkingOptions } from '@react-navigation/native';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import * as Linking from 'expo-linking';
import { ThemeProvider, useTheme } from './src/theme';
import { AppProvider } from './src/store/AppContext';
import { RootNavigator } from './src/navigation/RootNavigator';

// Fix 16: Deep linking configuration
const prefix = Linking.createURL('/');

const linking: LinkingOptions<any> = {
  prefixes: [prefix, 'krezus://'],
  config: {
    screens: {
      Onboarding: {
        screens: {
          Activation: 'activate',
        },
      },
      MainTabs: {
        screens: {
          Accueil: {
            screens: {
              HomeMain: 'home',
              StockDetail: 'stock/:stockId',
            },
          },
          Apprendre: 'learn',
          Notifications: 'notifications',
          Profil: 'profile',
        },
      },
    },
  },
};

const AppContent = () => {
  const { isDark } = useTheme();
  return (
    <>
      <StatusBar style={isDark ? 'light' : 'dark'} />
      <NavigationContainer linking={linking}>
        <RootNavigator />
      </NavigationContainer>
    </>
  );
};

export default function App() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <ThemeProvider>
          <AppProvider>
            <AppContent />
          </AppProvider>
        </ThemeProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}
