import React, { ReactNode } from 'react';
import { View, StyleSheet, ViewStyle } from 'react-native';
import { useTheme, BorderRadius, Spacing } from '../../theme';

interface GlassCardProps {
  children: ReactNode;
  style?: ViewStyle;
  onPress?: () => void;
}

export const GlassCard = ({ children, style }: GlassCardProps) => {
  const { colors } = useTheme();

  return (
    <View style={[
      styles.card,
      {
        backgroundColor: colors.glass,
        borderColor: colors.glassBorder,
      },
      style,
    ]}>
      {children}
    </View>
  );
};

const styles = StyleSheet.create({
  card: {
    borderRadius: BorderRadius.lg,
    borderWidth: 1,
    padding: Spacing.md,
    overflow: 'hidden',
  },
});
