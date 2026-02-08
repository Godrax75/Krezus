import React, { ReactNode } from 'react';
import { View, TouchableOpacity, StyleSheet, ViewStyle } from 'react-native';
import { useTheme, BorderRadius, Spacing } from '../../theme';

interface GlassCardProps {
  children: ReactNode;
  style?: ViewStyle;
  onPress?: () => void;
}

export const GlassCard = ({ children, style, onPress }: GlassCardProps) => {
  const { colors } = useTheme();

  const cardStyle = [
    styles.card,
    {
      backgroundColor: colors.glass,
      borderColor: colors.glassBorder,
    },
    style,
  ];

  if (onPress) {
    return (
      <TouchableOpacity activeOpacity={0.7} onPress={onPress} style={cardStyle}>
        {children}
      </TouchableOpacity>
    );
  }

  return (
    <View style={cardStyle}>
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
