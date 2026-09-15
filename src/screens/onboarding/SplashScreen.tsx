import React, { useEffect, useRef } from 'react';
import { View, Text, Animated, StyleSheet } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useTheme } from '../../theme';
import { FontSize, FontWeight } from '../../theme';

const SplashScreen: React.FC = () => {
  const { colors } = useTheme();
  const navigation = useNavigation<any>();

  const logoOpacity = useRef(new Animated.Value(0)).current;
  const lineScaleX = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    Animated.sequence([
      Animated.timing(logoOpacity, {
        toValue: 1,
        duration: 800,
        useNativeDriver: true,
      }),
      Animated.timing(lineScaleX, {
        toValue: 1,
        duration: 500,
        useNativeDriver: true,
      }),
    ]).start();

    const timeout = setTimeout(() => {
      navigation.replace('Welcome');
    }, 2000);

    return () => clearTimeout(timeout);
  }, [logoOpacity, lineScaleX, navigation]);

  return (
    <View style={[styles.container, { backgroundColor: '#0A0A0A' }]}>
      <Animated.Text
        style={[
          styles.logo,
          {
            color: '#C9A84C',
            opacity: logoOpacity,
          },
        ]}
      >
        KREZUS
      </Animated.Text>
      <Animated.View
        style={[
          styles.goldLine,
          {
            backgroundColor: '#C9A84C',
            transform: [{ scaleX: lineScaleX }],
          },
        ]}
      />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  logo: {
    fontSize: 48,
    fontWeight: FontWeight.bold as any,
    letterSpacing: 8,
  },
  goldLine: {
    width: 60,
    height: 3,
    marginTop: 16,
    borderRadius: 2,
  },
});

export default SplashScreen;
