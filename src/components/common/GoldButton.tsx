import React from 'react';
import { TouchableOpacity, Text, StyleSheet, ViewStyle, ActivityIndicator } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { useTheme, BorderRadius, FontSize, FontWeight, Spacing } from '../../theme';

interface GoldButtonProps {
  title: string;
  onPress: () => void;
  style?: ViewStyle;
  disabled?: boolean;
  loading?: boolean;
  variant?: 'filled' | 'outline';
}

export const GoldButton = ({ title, onPress, style, disabled, loading, variant = 'filled' }: GoldButtonProps) => {
  const { colors } = useTheme();

  if (variant === 'outline') {
    return (
      <TouchableOpacity
        style={[styles.button, { borderWidth: 1.5, borderColor: colors.primary }, style]}
        onPress={onPress}
        disabled={disabled || loading}
        activeOpacity={0.7}
      >
        <Text style={[styles.text, { color: colors.primary }]}>{title}</Text>
      </TouchableOpacity>
    );
  }

  return (
    <TouchableOpacity onPress={onPress} disabled={disabled || loading} activeOpacity={0.8} style={style}>
      <LinearGradient
        colors={disabled ? ['#555', '#444'] : ['#D4BA6A', '#C9A84C', '#A88A3A']}
        start={{ x: 0, y: 0 }}
        end={{ x: 1, y: 1 }}
        style={[styles.button, styles.gradient]}
      >
        {loading ? (
          <ActivityIndicator color="#0A0A0A" />
        ) : (
          <Text style={[styles.text, { color: '#0A0A0A' }]}>{title}</Text>
        )}
      </LinearGradient>
    </TouchableOpacity>
  );
};

const styles = StyleSheet.create({
  button: {
    height: 56,
    borderRadius: BorderRadius.lg,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: Spacing.xl,
  },
  gradient: {
    width: '100%',
  },
  text: {
    fontSize: FontSize.lg,
    fontWeight: FontWeight.semibold,
  },
});
