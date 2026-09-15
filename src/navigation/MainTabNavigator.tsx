import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { Ionicons } from '@expo/vector-icons';
import { useTheme, FontSize, FontWeight } from '../theme';
import { useApp } from '../store/AppContext';
import { HomeScreen } from '../screens/home/HomeScreen';
import { StockDetailScreen } from '../screens/stockDetail/StockDetailScreen';
import { LearnScreen } from '../screens/learn/LearnScreen';
import { ModuleDetailScreen } from '../screens/learn/ModuleDetailScreen';
import { NotificationsScreen } from '../screens/notifications/NotificationsScreen';
import { ProfileScreen } from '../screens/profile/ProfileScreen';
import { LegalScreen } from '../screens/legal/LegalScreen';
import { LegalDocumentId } from '../data/legalContent';

export type HomeStackParamList = {
  HomeMain: undefined;
  StockDetail: { stockId: string };
};

export type LearnStackParamList = {
  LearnMain: undefined;
  ModuleDetail: { moduleId: string };
};

export type ProfileStackParamList = {
  ProfileMain: undefined;
  Legal: { document: LegalDocumentId };
};

const HomeStack = createNativeStackNavigator<HomeStackParamList>();
const LearnStack = createNativeStackNavigator<LearnStackParamList>();
const ProfileStack = createNativeStackNavigator<ProfileStackParamList>();
const Tab = createBottomTabNavigator();

// Fix 7: Use dynamic colors from theme instead of hardcoded '#0A0A0A'
const HomeStackNavigator = () => {
  const { colors } = useTheme();
  return (
    <HomeStack.Navigator screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.background } }}>
      <HomeStack.Screen name="HomeMain" component={HomeScreen} />
      <HomeStack.Screen name="StockDetail" component={StockDetailScreen} options={{ animation: 'slide_from_right' }} />
    </HomeStack.Navigator>
  );
};

const LearnStackNavigator = () => {
  const { colors } = useTheme();
  return (
    <LearnStack.Navigator screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.background } }}>
      <LearnStack.Screen name="LearnMain" component={LearnScreen} />
      <LearnStack.Screen name="ModuleDetail" component={ModuleDetailScreen} options={{ animation: 'slide_from_right' }} />
    </LearnStack.Navigator>
  );
};

const ProfileStackNavigator = () => {
  const { colors } = useTheme();
  return (
    <ProfileStack.Navigator screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.background } }}>
      <ProfileStack.Screen name="ProfileMain" component={ProfileScreen} />
      <ProfileStack.Screen name="Legal" component={LegalScreen} options={{ animation: 'slide_from_right' }} />
    </ProfileStack.Navigator>
  );
};

export const MainTabNavigator = () => {
  const { colors } = useTheme();
  const { unreadCount } = useApp();

  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        headerShown: false,
        // Fix 13: subtle fade animation between tabs
        animation: 'fade',
        tabBarStyle: {
          backgroundColor: colors.tabBar,
          borderTopColor: colors.border,
          borderTopWidth: 0.5,
          height: 88,
          paddingBottom: 30,
          paddingTop: 8,
        },
        // Fix 7: dynamic sceneStyle for tab screens
        sceneStyle: { backgroundColor: colors.background },
        tabBarActiveTintColor: colors.primary,
        tabBarInactiveTintColor: colors.textTertiary,
        tabBarLabelStyle: {
          fontSize: FontSize.xs,
          fontWeight: FontWeight.medium,
        },
        tabBarIcon: ({ focused, color }) => {
          let iconName: keyof typeof Ionicons.glyphMap = 'home';

          switch (route.name) {
            case 'Accueil':
              iconName = focused ? 'home' : 'home-outline';
              break;
            case 'Apprendre':
              iconName = focused ? 'book' : 'book-outline';
              break;
            case 'Notifications':
              iconName = focused ? 'notifications' : 'notifications-outline';
              break;
            case 'Profil':
              iconName = focused ? 'person' : 'person-outline';
              break;
          }

          return (
            <View>
              <Ionicons name={iconName} size={24} color={color} />
              {route.name === 'Notifications' && unreadCount > 0 && (
                <View style={[styles.badge, { backgroundColor: colors.notification }]}>
                  <Text style={styles.badgeText}>{unreadCount > 9 ? '9+' : unreadCount}</Text>
                </View>
              )}
            </View>
          );
        },
      })}
    >
      <Tab.Screen name="Accueil" component={HomeStackNavigator} />
      <Tab.Screen name="Apprendre" component={LearnStackNavigator} />
      <Tab.Screen name="Notifications" component={NotificationsScreen} />
      <Tab.Screen name="Profil" component={ProfileStackNavigator} />
    </Tab.Navigator>
  );
};

const styles = StyleSheet.create({
  badge: {
    position: 'absolute',
    right: -8,
    top: -4,
    minWidth: 18,
    height: 18,
    borderRadius: 9,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 4,
  },
  badgeText: {
    color: '#FFFFFF',
    fontSize: 10,
    fontWeight: '700',
  },
});
