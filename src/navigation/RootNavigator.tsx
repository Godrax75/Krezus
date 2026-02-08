import React from 'react';
import { View, Text, StyleSheet, Animated } from 'react-native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { useApp } from '../store/AppContext';
import { useTheme } from '../theme';
import { OnboardingNavigator } from './OnboardingNavigator';
import { MainTabNavigator } from './MainTabNavigator';

export type RootStackParamList = {
  Onboarding: undefined;
  MainTabs: undefined;
};

const Stack = createNativeStackNavigator<RootStackParamList>();

const LoadingScreen = () => {
  const { colors } = useTheme();
  const opacity = React.useRef(new Animated.Value(0.3)).current;

  React.useEffect(() => {
    const anim = Animated.loop(
      Animated.sequence([
        Animated.timing(opacity, { toValue: 1, duration: 800, useNativeDriver: true }),
        Animated.timing(opacity, { toValue: 0.3, duration: 800, useNativeDriver: true }),
      ])
    );
    anim.start();
    return () => anim.stop();
  }, [opacity]);

  return (
    <View style={[styles.loadingContainer, { backgroundColor: colors.background }]}>
      <Animated.Text style={[styles.loadingLogo, { color: colors.primary, opacity }]}>
        KREZUS
      </Animated.Text>
    </View>
  );
};

export const RootNavigator = () => {
  const { isOnboarded, isAuthenticated, isLoading } = useApp();

  if (isLoading) {
    return <LoadingScreen />;
  }

  return (
    <Stack.Navigator screenOptions={{ headerShown: false, animation: 'fade' }}>
      {!isOnboarded || !isAuthenticated ? (
        <Stack.Screen name="Onboarding" component={OnboardingNavigator} />
      ) : (
        <Stack.Screen name="MainTabs" component={MainTabNavigator} />
      )}
    </Stack.Navigator>
  );
};

const styles = StyleSheet.create({
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  loadingLogo: {
    fontSize: 32,
    fontWeight: '700',
    letterSpacing: 6,
  },
});
