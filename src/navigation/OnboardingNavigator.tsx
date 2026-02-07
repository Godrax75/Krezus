import React from 'react';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import SplashScreen from '../screens/onboarding/SplashScreen';
import WelcomeScreen from '../screens/onboarding/WelcomeScreen';
import ActivationScreen from '../screens/onboarding/ActivationScreen';
import SignupScreen from '../screens/onboarding/SignupScreen';
import RevealScreen from '../screens/onboarding/RevealScreen';

export type OnboardingStackParamList = {
  Splash: undefined;
  Welcome: undefined;
  Activation: undefined;
  Signup: undefined;
  Reveal: undefined;
};

const Stack = createNativeStackNavigator<OnboardingStackParamList>();

export const OnboardingNavigator = () => {
  return (
    <Stack.Navigator
      screenOptions={{
        headerShown: false,
        animation: 'fade',
        contentStyle: { backgroundColor: '#0A0A0A' },
      }}
    >
      <Stack.Screen name="Splash" component={SplashScreen} />
      <Stack.Screen name="Welcome" component={WelcomeScreen} />
      <Stack.Screen name="Activation" component={ActivationScreen} />
      <Stack.Screen name="Signup" component={SignupScreen} />
      <Stack.Screen name="Reveal" component={RevealScreen} />
    </Stack.Navigator>
  );
};
