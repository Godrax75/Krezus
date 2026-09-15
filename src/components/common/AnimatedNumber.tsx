import React, { useEffect, useRef, useState } from 'react';
import { Text, TextStyle, Animated, StyleProp } from 'react-native';

interface AnimatedNumberProps {
  value: number;
  prefix?: string;
  suffix?: string;
  decimals?: number;
  style?: StyleProp<TextStyle>;
  duration?: number;
}

export const AnimatedNumber = ({ value, prefix = '', suffix = '', decimals = 2, style, duration = 1000 }: AnimatedNumberProps) => {
  const animatedValue = useRef(new Animated.Value(0)).current;
  const [displayValue, setDisplayValue] = useState('0');

  useEffect(() => {
    animatedValue.setValue(0);
    Animated.timing(animatedValue, {
      toValue: value,
      duration,
      useNativeDriver: false,
    }).start();

    const listener = animatedValue.addListener(({ value: v }) => {
      setDisplayValue(v.toFixed(decimals));
    });

    return () => animatedValue.removeListener(listener);
  }, [value, decimals, duration, animatedValue]);

  return (
    <Text style={style}>
      {prefix}{displayValue}{suffix}
    </Text>
  );
};
